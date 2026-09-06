import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const swift = readFileSync(new URL('../ios/BrowserModel.swift', import.meta.url), 'utf8');
const script = swift.match(/private static let actionScript = #"""\r?\n([\s\S]*?)\r?\n\s*"""#/)[1];
const snapshot = swift.match(/private static let snapshotScript = #"""\r?\n([\s\S]*?)\r?\n\s*"""#/)[1];
new vm.Script(snapshot);
function run(action, overrides = {}) {
  class Input { set value(v) { this.stored = v; } get value() { return this.stored; } }
  const element = Object.assign(new Input(), {tagName:'INPUT',type:'text',isConnected:true,getClientRects:()=>[{}],dispatchEvent:()=>{},autocomplete:''}, overrides);
  const context = { action, atlasNodes:new Map([['1',element]]), HTMLInputElement:Input, Event:class {}, window:{scrollBy(){}},innerHeight:800 };
  return vm.runInNewContext(`(function(){${script}})()`, context);
}
test('preenche valor literal sem executar JavaScript do texto', () => {
  assert.equal(run({kind:'fill',target:'1',value:'"; alert(1); //'}),'Campo preenchido e valor verificado.');
});
test('rejeita senha, upload e campo removido', () => {
  for (const type of ['password','file','hidden']) assert.throws(()=>run({kind:'fill',target:'1',value:'x'},{type}),/não suportado/);
  assert.throws(()=>run({kind:'fill',target:'1',value:'x'},{isConnected:false}),/indisponível/);
});
test('rejeita alvo desconhecido e ações fora da lista', () => {
  assert.throws(()=>run({kind:'fill',target:'2',value:'x'}),/indisponível/);
  assert.throws(()=>run({kind:'eval',target:'1',value:'x'}),/não suportada/);
});
test('rejeita autocomplete de cartão e código temporário', () => {
  for (const autocomplete of ['cc-number','one-time-code']) assert.throws(()=>run({kind:'fill',target:'1',value:'x'},{autocomplete}),/manualmente/);
});
