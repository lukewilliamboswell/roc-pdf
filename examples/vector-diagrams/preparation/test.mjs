import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {browser, resolveSvg} from './prepare.mjs';

const here=path.dirname(fileURLToPath(import.meta.url));
const valid=(extra='',attributes='')=>`<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10 -10 120 100">${extra}<path id="shape" d="M0 0 L40 0 L40 30 Z" fill="#183454" stroke="none" ${attributes}/></svg>`;
const label=(text,attributes='')=>`<g style="font-family:VectorInter;font-size:16px;font-kerning:none;font-variant-ligatures:none"><text id="label" x="15" y="40" ${attributes}>${text}</text></g>`;
const marker='<defs><marker id="arrow" orient="auto" markerUnits="userSpaceOnUse" markerWidth="10" markerHeight="10" viewBox="0 0 10 10" refX="5" refY="5" style="overflow:visible"><path d="M0 0 L10 5 L0 10 Z" stroke="none"/></marker></defs>';
const cases=[
  ['HTML labels', valid('<foreignObject id="html" width="20" height="10"/>'), 'vector.element at #html'],
  ['referenced filter',valid('<defs><filter id="effect"/></defs>','filter="url(#effect)"'),'vector.effect at #shape'],
  ['referenced gradient',valid('<defs><linearGradient id="gradient"/></defs>','style="fill:url(#gradient)"'),'vector.paint at #shape'],
  ['external image',valid('<image id="external" href="https://example.org/image.png"/>'),'vector.element at #external'],
  ['external CSS',valid('<style>@import "https://example.org/theme.css";</style>'),'vector.external at style'],
  ['invalid geometry',valid().replace('M0 0 L40 0 L40 30 Z','M0 0 L1e999 2'),'vector.geometry at #shape'],
  ['unsupported transform',valid('','transform="rotate(20)"'),'vector.transform at #shape'],
  ['escaping geometry',valid().replace('M0 0','M-100 0'),'vector.geometry at svg'],
  ['unsupported arc',valid().replace('M0 0 L40 0 L40 30 Z','M0 0 A20 20 0 0 0 40 30'),'vector.geometry at #shape'],
  ['opacity',valid('','opacity="0.5"'),'vector.paint at #shape'],
  ['text decoration',valid(label('Café','text-decoration="underline"')),'vector.text at #label'],
  ['per-character positioning',valid(label('Café','rotate="10"')),'vector.text at #label'],
  ['Roc interpolation',valid(label('${danger()}')),'vector.text at #label'],
  ['unsupported Unicode',valid(label('中')),'vector.text at #label'],
  ['stroked text',valid(label('Café','stroke="#000000" stroke-miterlimit="10"')),'vector.text at #label'],
  ['oversize viewport',valid().replace('120 100','1e100 100'),'vector.geometry at svg'],
  ['direct line opacity',valid(label('<tspan id="row" opacity="0.5">Café</tspan>')),'vector.paint at #row'],
  ['direct line filter',valid('<defs><filter id="effect"/></defs>'+label('<tspan id="row" filter="url(#effect)">Café</tspan>')),'vector.effect at #row'],
  ['direct line clip',valid('<defs><clipPath id="clip"/></defs>'+label('<tspan id="row" clip-path="url(#clip)">Café</tspan>')),'vector.effect at #row'],
  ['direct line transform',valid(label('<tspan id="row" transform="translate(2)">Café</tspan>')),'vector.transform at #row'],
  ['closed marker path',valid(marker,'marker-end="url(#arrow)"'),'vector.marker at #shape'],
  ['multiple marker subpaths',valid(marker,'marker-end="url(#arrow)"').replace('M0 0 L40 0 L40 30 Z','M0 0 L10 0 M20 0 L40 0'),'vector.marker at #shape'],
  ['collapsed whitespace',valid(label('Café  order')),'vector.text at #label'],
  ['leading whitespace',valid(label(' Café')),'vector.text at #label'],
  ['visible descendant effect',valid('<defs><filter id="effect"/></defs><g visibility="hidden"><path id="visible" visibility="visible" filter="url(#effect)" d="M0 0 L10 0 L10 10 Z"/></g>'),'vector.effect at #visible'],
];
const chrome=await browser();
try{
  const page=await chrome.newPage();
  await page.setRequestInterception(true);
  page.on('request',request=>request.url().startsWith('data:')?request.continue():request.abort());
  const font=await fs.readFile(path.join(here,'../fonts/Inter-Regular.ttf'));
  await page.setContent(`<style>body{margin:0}@font-face{font-family:VectorInter;src:url(data:font/ttf;base64,${font.toString('base64')})}</style>`);
  await page.evaluate(()=>document.fonts.load('16px VectorInter'));
  const svg=await fs.readFile(path.join(here,'diagram.svg'),'utf8');
  const resolved=await page.evaluate(resolveSvg,svg);
  assert.deepEqual(resolved,JSON.parse(await fs.readFile(path.join(here,'resolved.json'),'utf8')));
  const unused=await page.evaluate(resolveSvg,valid('<defs><filter id="unused"/><linearGradient id="unused-gradient"/></defs>'));
  assert.equal(unused.paths.length,1);
  const visible=await page.evaluate(resolveSvg,valid('<g visibility="hidden"><path id="override" visibility="visible" d="M50 20 L60 20 L60 30 Z"/></g>'));
  assert.equal(visible.paths.length,2,'visible descendants must survive hidden ancestors');
  console.log('PASS descendant visibility override');
  for(const [name,input,expected] of cases){
    await assert.rejects(()=>page.evaluate(resolveSvg,input),error=>error.message.includes(expected),name);
    console.log(`PASS ${name}`);
  }
  const live=await fs.readFile(path.join(here,'../../../tests/vector_diagrams/html-labels.svg'),'utf8');
  await assert.rejects(()=>page.evaluate(resolveSvg,live),error=>error.message.includes('vector.element at foreignObject'));
  console.log('PASS original consumer HTML-label SVG rejection');
  console.log('PASS deterministic resolved Mermaid output and unused effects');
}finally{await chrome.close();}
