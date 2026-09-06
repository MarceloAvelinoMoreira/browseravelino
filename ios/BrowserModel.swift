import Foundation
import Combine
import WebKit

struct BrowserAction: Codable {
    let kind: String
    let target: String
    let value: String
    let message: String
}

private struct StepRequest: Encodable {
    let goal: String
    let page: String
    let history: [String]
}

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let web = WKWebView()
    @Published var address = "https://example.com"
    @Published var endpoint = ""
    @Published var token = ""
    @Published var sharePage = false
    @Published var running = false
    @Published var pending: BrowserAction?
    @Published var messages = ["Abra um site e peça uma tarefa. Configure a conexão com a IA na engrenagem."]
    private var task: Task<Void, Never>?
    private var approval: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = true
        openAddress()
    }

    func navigationPolicy(_ url: URL?) -> Bool { url?.scheme == "https" && url?.host != nil }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationPolicy(navigationAction.request.url) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        address = webView.url?.absoluteString ?? address
    }

    func openAddress() {
        let candidate = address.contains("://") ? address : "https://" + address
        guard let url = URL(string: candidate), navigationPolicy(url) else {
            messages.append("Use um endereço HTTPS válido."); return
        }
        web.load(URLRequest(url: url))
    }

    func confirm(_ allowed: Bool) {
        let continuation = approval
        approval = nil
        pending = nil
        continuation?.resume(returning: allowed)
    }

    func stop() {
        task?.cancel()
        confirm(false)
    }

    func start(_ goal: String) {
        guard !running else { return }
        guard sharePage else { messages.append("Ative o compartilhamento da página para executar a tarefa."); return }
        guard let base = URL(string: endpoint), base.scheme == "https", base.host != nil, !token.isEmpty else {
            messages.append("Configure a URL HTTPS do servidor e o token na engrenagem."); return
        }
        messages.append("Você: " + goal)
        running = true
        task = Task {
            defer { running = false; task = nil; confirm(false) }
            do {
                var history: [String] = []
                for _ in 0..<8 {
                    try Task.checkCancellation()
                    let page = try await snapshot()
                    var request = URLRequest(url: base.appendingPathComponent("step"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 55
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONEncoder().encode(StepRequest(goal: goal, page: page, history: history))
                    let (data, response) = try await URLSession.shared.data(for: request)
                    try Task.checkCancellation()
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw failure("Falha na conexão com a IA. Confira servidor, token e configuração do provedor.")
                    }
                    let action = try JSONDecoder().decode(BrowserAction.self, from: data)
                    if action.kind == "answer" { messages.append(action.message); return }
                    if action.kind == "click" || action.kind == "navigate" {
                        pending = action
                        let allowed = await withCheckedContinuation { approval = $0 }
                        guard allowed else { throw CancellationError() }
                    }
                    try Task.checkCancellation()
                    // Re-read before acting: never act on a page that changed during inference/review.
                    guard try await snapshot() == page else {
                        history.append("A página mudou; a ação proposta foi descartada.")
                        continue
                    }
                    let result = try await execute(action)
                    history.append("\(action.kind) \(action.target): \(result)")
                    messages.append(action.message + "\n" + result)
                    try await Task.sleep(for: .milliseconds(900))
                    var attempts = 0
                    while web.isLoading && attempts < 40 {
                        try await Task.sleep(for: .milliseconds(250)); attempts += 1
                    }
                    if web.isLoading { throw failure("A página ainda está carregando. Aguarde e tente novamente.") }
                }
                messages.append("Limite de 8 etapas atingido. Confira a página antes de continuar.")
            } catch {
                messages.append(Task.isCancelled || error is CancellationError ? "Tarefa interrompida. Ações já executadas permanecem na página." : error.localizedDescription)
            }
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Atlas", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func snapshot() async throws -> String {
        // Isolated world keeps page scripts from replacing our element registry.
        let result = try await web.evaluateJavaScript(Self.snapshotScript, in: nil, in: .defaultClient)
        guard let value = result as? String else { throw failure("Não foi possível ler esta página.") }
        return value
    }

    private func execute(_ action: BrowserAction) async throws -> String {
        if action.kind == "navigate" {
            guard let url = URL(string: action.target), navigationPolicy(url) else { throw failure("Navegação exige HTTPS.") }
            web.load(URLRequest(url: url))
            return "Navegação iniciada."
        }
        let data = try JSONEncoder().encode(action)
        let json = String(decoding: data, as: UTF8.self)
        let script = "const action = \(json);\n" + Self.actionScript
        let result = try await web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .defaultClient)
        return result as? String ?? "Ação executada; verifique a página."
    }

    private static let snapshotScript = #"""
    (() => {
      const visible = e => !!(e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden');
      const nodes = [...document.querySelectorAll('a,button,input,textarea,select,[role="button"]')]
        .filter(e => visible(e) && !['password','hidden'].includes(e.type)).slice(0,160);
      if (!globalThis.atlasIDs) { globalThis.atlasIDs = new WeakMap(); globalThis.atlasNext = 0; }
      globalThis.atlasNodes = new Map();
      const elements = nodes.map(e => {
        if (!atlasIDs.has(e)) atlasIDs.set(e, String(++globalThis.atlasNext));
        const id = atlasIDs.get(e);
        atlasNodes.set(id,e);
        return {id, tag:e.tagName, type:e.type || '', label:(e.labels?.[0]?.innerText || e.getAttribute('aria-label') || e.innerText || e.placeholder || e.name || '').slice(0,180),
          options:e.tagName === 'SELECT' ? [...e.options].map(o=>({text:o.text,value:o.value})).slice(0,60) : undefined};
      });
      return JSON.stringify({url:location.href,title:document.title,text:(document.body?.innerText || '').slice(0,18000),elements});
    })()
    """#

    private static let actionScript = #"""
    if (action.kind === 'scroll') {
      if (!['up','down'].includes(action.target)) throw new Error('Direção inválida.');
      window.scrollBy(0, innerHeight * (action.target === 'up' ? -0.75 : 0.75));
      return 'Página rolada.';
    }
    const e = globalThis.atlasNodes?.get(action.target);
    if (!e || !e.isConnected || !e.getClientRects().length || e.disabled) throw new Error('Elemento indisponível.');
    if (action.kind === 'click') { e.click(); return 'Clique executado; resultado será relido.'; }
    if (action.kind !== 'fill') throw new Error('Ação não suportada.');
    if (!['INPUT','TEXTAREA','SELECT'].includes(e.tagName) || e.readOnly) throw new Error('Campo não editável.');
    if (['password','hidden','file','submit','button','checkbox','radio'].includes(e.type)) throw new Error('Tipo de campo não suportado.');
    if (/cc-|one-time-code/.test(e.autocomplete)) throw new Error('Preencha esse campo manualmente.');
    if (e.tagName === 'SELECT' && ![...e.options].some(o => o.value === action.value)) throw new Error('Opção inexistente.');
    const proto = e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : e.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto,'value').set.call(e,action.value);
    e.dispatchEvent(new Event('input',{bubbles:true}));
    e.dispatchEvent(new Event('change',{bubbles:true}));
    return e.value === action.value ? 'Campo preenchido e valor verificado.' : 'O site alterou ou rejeitou o valor; confira o campo.';
    """#
}
