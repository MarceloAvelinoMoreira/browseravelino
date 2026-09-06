import SwiftUI
import WebKit

@main
struct AtlasBrowserApp: App {
    var body: some Scene { WindowGroup { BrowserScreen() } }
}

struct BrowserView: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserScreen: View {
    @StateObject private var model = BrowserModel()
    @State private var prompt = ""
    @State private var settings = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("◈ Atlas").font(.title3.bold())
                Button { model.web.goBack() } label: { Image(systemName: "chevron.left") }
                Button { model.web.goForward() } label: { Image(systemName: "chevron.right") }
                TextField("https://…", text: $model.address).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().onSubmit { model.openAddress() }
                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                Button { model.web.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button { settings = true } label: { Image(systemName: "gearshape") }
            }.padding().disabled(model.running)
            Divider()
            HStack(spacing: 0) {
                BrowserView(web: model.web)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    Label("Seu assistente", systemImage: "sparkles").font(.title2.bold())
                    Text("Converse com a página aberta.").foregroundStyle(.secondary)
                    Toggle("Compartilhar página com a IA", isOn: $model.sharePage)
                        .font(.caption).disabled(model.running)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(model.messages.enumerated()), id: \.offset) { _, message in
                                Text(message).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    if let action = model.pending {
                        VStack(alignment: .leading) {
                            Text("Revisar ação").bold()
                            Text(action.message)
                            Text("\(action.kind): \(action.target)").font(.caption).textSelection(.enabled)
                            Button("Executar esta ação") { model.confirm(true) }.buttonStyle(.borderedProminent)
                            Button("Cancelar tarefa") { model.stop() }
                        }.padding().background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if model.running { Button("Parar tarefa", role: .destructive) { model.stop() } }
                    TextField("Peça para ler ou preencher…", text: $prompt, axis: .vertical)
                        .lineLimit(2...5).textFieldStyle(.roundedBorder)
                    Button("Enviar", systemImage: "arrow.up") {
                        model.start(prompt); prompt = ""
                    }.buttonStyle(.borderedProminent).disabled(model.running || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(20).frame(width: 320)
            }
        }.sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    TextField("URL HTTPS do servidor", text: $model.endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Token do protótipo", text: $model.token)
                    Text("O token fica em memória. A chave da OpenAI deve ficar somente no servidor.")
                }.navigationTitle("Conectar IA").toolbar { Button("Concluído") { settings = false } }
            }
        }
    }
}
