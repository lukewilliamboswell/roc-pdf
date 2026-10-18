/** Authoring-only Mermaid/SVG preparation. Never imported by the Roc package. */
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import puppeteer from 'puppeteer';

const directory = path.dirname(fileURLToPath(import.meta.url));
const example = path.dirname(directory);
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

// Runs in the preparation browser. All geometry and paint become explicit
// facts here; Roc subsequently performs its own validation and text shaping.
export function resolveSvg(source) {
  const fail = (element, property, detail) => {
    const location = element.id ? `#${element.id}` : element.tagName;
    throw new Error(`vector.${property} at ${location}: ${detail}`);
  };
  if (source.length > 1000000 || /<!DOCTYPE|<!ENTITY/i.test(source)) throw new Error('vector.xml: input size or DTD outside profile');
  const parsed = new DOMParser().parseFromString(source, 'image/svg+xml');
  if (parsed.querySelector('parsererror')) throw new Error('vector.xml: malformed SVG');
  const root = parsed.documentElement;
  if (root.localName !== 'svg') fail(root, 'root', 'expected SVG');
  if (source.length > 1000000 || root.querySelectorAll('*').length > 10000) fail(root, 'budget', 'input limit');
  // Inspect before attachment: no active content, resource requests, or HTML.
  for (const el of [root, ...root.querySelectorAll('*')]) {
    if (['script', 'foreignObject', 'image', 'use', 'a', 'animate', 'animateTransform', 'set'].includes(el.localName)) fail(el, 'element', 'unsupported active, HTML, or external element');
    for (const attr of el.attributes) {
      if (/^on/i.test(attr.name) || /(?:href|src)$/i.test(attr.name)) fail(el, 'external', 'references are not accepted');
      for (const match of attr.value.matchAll(/url\(([^)]+)\)/g)) {
        if (!/^['"]?#[A-Za-z0-9_-]+['"]?$/.test(match[1])) fail(el, 'external', 'only local definitions are accepted');
      }
    }
    if (el.localName === 'style' && /@(?:import|font-face)|url\(\s*['"]?(?!#)/i.test(el.textContent)) fail(el, 'external', 'external CSS is not accepted');
  }
  const view = root.viewBox.baseVal;
  const box = { x: view.x, y: view.y, width: view.width, height: view.height };
  if (!Object.values(box).every(Number.isFinite) || box.width <= 0 || box.height <= 0 || Math.max(...Object.values(box).map(Math.abs)) > 1000000) fail(root, 'geometry', 'positive finite viewBox required');
  root.setAttribute('width', `${box.width}`);
  root.setAttribute('height', `${box.height}`);
  root.style.maxWidth = 'none';
  root.style.maxHeight = 'none';
  root.style.width = `${box.width}px`;
  root.style.height = `${box.height}px`;
  document.body.replaceChildren(document.importNode(root, true));
  const svg = document.querySelector('svg');
  const screen=svg.getScreenCTM();
  const rootMatrix = new DOMMatrix([screen.a,screen.b,screen.c,screen.d,screen.e,screen.f]).inverse();
  const paths = [], labels = [], paint = [];
  const point = (x, y, matrix) => {
    const p = new DOMPoint(x, y).matrixTransform(matrix);
    if (![p.x, p.y].every(Number.isFinite) || Math.max(Math.abs(p.x), Math.abs(p.y)) > 1000000) fail(svg, 'geometry', 'coordinate out of bounds');
    return [Math.round((p.x - box.x) * 750), Math.round((box.y + box.height - p.y) * 750)];
  };
  const matrixOf = el => {
    if (typeof el.getScreenCTM !== 'function') fail(el, 'element', 'unsupported graphics element');
    const matrix = rootMatrix.multiply(el.getScreenCTM());
    if (Math.abs(matrix.b) > 1e-8 || Math.abs(matrix.c) > 1e-8 || matrix.a <= 0 || Math.abs(matrix.a - matrix.d) > 1e-8) fail(el, 'transform', 'only translation and positive uniform scale are accepted');
    return matrix;
  };
  const number = (el, key, fallback = 0) => {
    const raw = el.getAttribute(key);
    const value = raw === null ? fallback : Number(raw);
    if (!Number.isFinite(value)) fail(el, 'geometry', `${key} must be a finite unitless number`);
    return value;
  };
  const color = (el, raw) => {
    if (raw === 'none') return null;
    const match = /^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)$/.exec(raw);
    if (!match) fail(el, 'paint', `unsupported color ${raw}`);
    if (match[4] !== undefined && Number(match[4]) === 0) return null;
    if (match[4] !== undefined && Number(match[4]) !== 1) fail(el, 'paint', 'transparent paint');
    return match.slice(1, 4).map(Number);
  };
  const styleOf = (el, matrix) => {
    const s = getComputedStyle(el);
    if (s.paintOrder !== 'normal') fail(el, 'paint', 'unsupported paint order');
    for (const key of ['filter', 'clipPath', 'mask', 'mixBlendMode']) {
      if (!['none', 'normal'].includes(s[key])) fail(el, 'effect', `${key}=${s[key]}`);
    }
    if (s.animationName !== 'none') fail(el, 'effect', 'animation');
    if ([s.opacity, s.fillOpacity, s.strokeOpacity].some(v => Number(v) !== 1)) fail(el, 'paint', 'opacity must be one');
    if (s.vectorEffect !== 'none' || s.fillRule !== 'nonzero') fail(el, 'paint', 'unsupported fill or vector effect');
    const fill = color(el, s.fill), stroke = color(el, s.stroke);
    let width = parseFloat(s.strokeWidth) * matrix.a * 750;
    if (stroke && width > 0) {
      if (s.strokeLinecap !== 'butt' || s.strokeLinejoin !== 'miter' || Number(s.strokeMiterlimit) !== 10) fail(el, 'stroke', 'butt/miter/10 stroke required');
      if (s.strokeDasharray !== 'none') {
        const dashes = s.strokeDasharray.split(/[, ]+/).map(parseFloat);
        if (!dashes.every(Number.isFinite) || dashes.some((v, i) => v !== 0 && (i % 2 === 1 || dashes.length % 2 === 1))) fail(el, 'stroke', 'dashed strokes are unsupported');
      }
      if (!Number.isFinite(width) || width < 0.5) fail(el, 'stroke', 'stroke too small');
    } else width = 0;
    return { fill, stroke: width ? stroke : null, width: Math.round(width) };
  };
  const segmentsOf = el => {
    if (el.localName === 'rect') {
      if (number(el, 'rx') || number(el, 'ry')) fail(el, 'geometry', 'rounded rectangles are unsupported');
      const x = number(el, 'x'), y = number(el, 'y'), w = number(el, 'width'), h = number(el, 'height');
      if (w <= 0 || h <= 0) fail(el, 'geometry', 'rectangle dimensions must be positive');
      return [['M', x, y], ['L', x+w, y], ['L', x+w, y+h], ['L', x, y+h], ['Z']];
    }
    if (el.localName === 'line') return [['M',number(el,'x1'),number(el,'y1')], ['L',number(el,'x2'),number(el,'y2')]];
    if (['polygon', 'polyline'].includes(el.localName)) {
      const raw = el.getAttribute('points') || '';
      if (/[^\d\s,.+eE-]/.test(raw)) fail(el, 'geometry', 'invalid polygon');
      const values = raw.trim().split(/[\s,]+/).map(Number);
      if (values.length < 4 || values.length % 2 || !values.every(Number.isFinite)) fail(el, 'geometry', 'invalid polygon');
      const result = [];
      for (let i=0;i<values.length;i+=2) result.push([i ? 'L':'M', values[i], values[i+1]]);
      if (el.localName === 'polygon') result.push(['Z']);
      return result;
    }
    const source = el.getAttribute('d') || '';
    const token = /[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?/g;
    const values = source.match(token) || [];
    if (source.replace(token, '').replace(/[\s,]/g, '')) fail(el, 'geometry', 'invalid path token');
    let i=0, command='', x=0,y=0,sx=0,sy=0, control=null, last='';
    const result=[];
    const take=()=> { if (i>=values.length || /^[a-zA-Z]$/.test(values[i])) fail(el,'geometry','incomplete path'); const n=Number(values[i++]); if(!Number.isFinite(n))fail(el,'geometry','nonfinite path'); return n; };
    while (i<values.length) {
      if (/^[a-zA-Z]$/.test(values[i])) command=values[i++];
      const upper=command.toUpperCase(), relative=command!==upper;
      if (!'MLHVCSQTZ'.includes(upper) || !upper) fail(el,'geometry',`unsupported path command ${command}`);
      if (upper==='Z') { result.push(['Z']);x=sx;y=sy;control=null;last='Z';command='';continue; }
      const end=()=> { const a=take(),b=take();return [a+(relative?x:0),b+(relative?y:0)]; };
      if (upper==='M'||upper==='L') {const p=end();result.push([upper,...p]);[x,y]=p;if(upper==='M'){sx=x;sy=y;command=relative?'l':'L';}control=null;}
      else if(upper==='H'){x=take()+(relative?x:0);result.push(['L',x,y]);control=null;}
      else if(upper==='V'){y=take()+(relative?y:0);result.push(['L',x,y]);control=null;}
      else if(upper==='C'||upper==='S') {
        const a=upper==='C'?end():(['C','S'].includes(last)?[2*x-control[0],2*y-control[1]]:[x,y]);
        const b=end(),p=end();result.push(['C',...a,...b,...p]);control=b;[x,y]=p;
      } else {
        const a=upper==='Q'?end():(['Q','T'].includes(last)?[2*x-control[0],2*y-control[1]]:[x,y]),p=end();
        result.push(['C',x+2*(a[0]-x)/3,y+2*(a[1]-y)/3,p[0]+2*(a[0]-p[0])/3,p[1]+2*(a[1]-p[1])/3,...p]);control=a;[x,y]=p;
      }
      last=upper;
    }
    if (!result.length || result[0][0]!=='M') fail(el,'geometry','path must begin with move');
    return result;
  };
  const emitPath = (el, matrix, raw = segmentsOf(el)) => {
    const style=styleOf(el,matrix);
    if (!style.fill&&!style.stroke) return;
    const segments=raw.map(s=> {const out=[s[0]];for(let i=1;i<s.length;i+=2)out.push(...point(s[i],s[i+1],matrix));return out;});
    paths.push({ ...style, segments });
  };
  const addMarker = (el, raw, which) => {
    const value=getComputedStyle(el)[which==='start'?'markerStart':'markerEnd'];
    if (value==='none') return;
    if (raw.some(segment=>segment[0]==='Z') || raw.filter(segment=>segment[0]==='M').length!==1) fail(el,'marker','markers require one open subpath');
    const id=/#([^)'"\s]+)['"]?\)$/.exec(value)?.[1];
    const marker=id&&svg.querySelector(`[id="${CSS.escape(id)}"]`);
    if (!marker||marker.localName!=='marker') fail(el,'marker','local marker required');
    if(marker.getAttribute('orient')!=='auto'||!['userSpaceOnUse','strokeWidth',null].includes(marker.getAttribute('markerUnits')))fail(marker,'marker','unsupported marker orientation or units');
    if (getComputedStyle(marker).overflow !== 'visible') fail(marker,'marker','visible marker overflow required');
    styleOf(marker, matrixOf(el));
    if(marker.children.length!==1||marker.firstElementChild.localName!=='path')fail(marker,'marker','one supported path required');
    const mbox=marker.viewBox.baseVal, mw=number(marker,'markerWidth',3),mh=number(marker,'markerHeight',3);
    if(mbox.width<=0||mbox.height<=0||mw<=0||mh<=0||Math.abs(mw/mbox.width-mh/mbox.height)>1e-8)fail(marker,'marker','uniform marker viewBox required');
    const segments=raw.filter(s=>s[0]!=='Z');
    const first=segments[0].slice(-2), final=segments.at(-1).slice(-2);
    const neighbor=which==='start'?segments[1]?.slice(1,3):(segments.at(-1)[0]==='C'?segments.at(-1).slice(-4,-2):segments.at(-2)?.slice(-2));
    if(!neighbor)fail(el,'marker','path has no tangent');
    const end=which==='start'?first:final;
    const dx=which==='start'?neighbor[0]-end[0]:end[0]-neighbor[0],dy=which==='start'?neighbor[1]-end[1]:end[1]-neighbor[1],length=Math.hypot(dx,dy);
    if(!length)fail(el,'marker','zero tangent');
    const scale=mw/mbox.width*(marker.getAttribute('markerUnits')==='userSpaceOnUse'?1:parseFloat(getComputedStyle(el).strokeWidth));
    const rotation=new DOMMatrix([dx/length,dy/length,-dy/length,dx/length,end[0],end[1]]);
    const matrix=matrixOf(el).multiply(rotation).scale(scale).translate(-number(marker,'refX'),-number(marker,'refY'));
    const child=marker.firstElementChild;
    if(child.hasAttribute('transform') || getComputedStyle(child).transform !== 'none')fail(child,'marker','marker child transforms unsupported');
    // Stroke width needs the uniform scalar, not the rotated matrix's a.
    const style=styleOf(child,new DOMMatrix().scale(matrixOf(el).a*scale));
    const flattened=segmentsOf(child).map(s=>{const out=[s[0]];for(let i=1;i<s.length;i+=2)out.push(...point(s[i],s[i+1],matrix));return out;});
    paths.push({...style,segments:flattened});
  };
  const visit = (el, depth=0) => {
    if(depth>48)fail(el,"budget","SVG nesting exceeds 48");
    if (['defs','style','title','desc','metadata','marker','filter','linearGradient','radialGradient','clipPath','mask'].includes(el.localName)) return;
    if (el.localName==='rect') { const w=number(el,'width'), h=number(el,'height'); if(w<0||h<0)fail(el,'geometry','negative rectangle dimensions'); if(w===0||h===0)return; }
    const s=getComputedStyle(el);
    if(s.display==='none')return;
    const matrix=matrixOf(el);
    if(['svg','g'].includes(el.localName)){styleOf(el,matrix);for(const child of el.children)visit(child,depth+1);return;}
    if(s.visibility!=='visible')return;
    styleOf(el,matrix);
    if(['path','rect','line','polygon','polyline'].includes(el.localName)) {
      if (!color(el,s.fill) && (!color(el,s.stroke) || parseFloat(s.strokeWidth) === 0)) return;
      const raw=segmentsOf(el);emitPath(el,matrix,raw);
      if(s.markerMid!=='none')fail(el,'marker','marker-mid unsupported');
      addMarker(el,raw,'start');addMarker(el,raw,'end');
      const b=el.getBBox();paint.push({el,box:[b.x*matrix.a+matrix.e,b.y*matrix.a+matrix.f,b.width*matrix.a,b.height*matrix.a]});return;
    }
    if(el.localName!=='text')fail(el,'element','unsupported visible element');
    if (!el.textContent.trim()) return;
    if(el.hasAttribute('textLength')||el.querySelector('textPath')||s.writingMode!=='horizontal-tb')fail(el,'text','unsupported text layout');
    if(s.dominantBaseline!=='auto'&&s.dominantBaseline!=='alphabetic')fail(el,'text','alphabetic baseline required');
    const lines=el.children.length?[...el.children]:[el];
    if(el.children.length&&[...el.childNodes].some(n=>n.nodeType===3&&n.textContent.trim()))fail(el,'text','mixed line content');
    for(const line of lines){
      if(line!==el&&line.localName!=='tspan')fail(line,'text','tspan lines required');
      for (const child of line.querySelectorAll('*')) {
        if(child.hasAttribute('rotate')||child.hasAttribute('textLength'))fail(child,'text','per-character positioning unsupported');
        const cs=getComputedStyle(child), ps=getComputedStyle(line);
        styleOf(child,matrix);
        if(child.localName!=='tspan'||['fontFamily','fontSize','fontWeight','fontStyle','fill','letterSpacing','wordSpacing','textAnchor','textTransform','fontKerning','fontVariantLigatures','textDecorationLine','baselineShift','webkitTextStrokeWidth'].some(k=>cs[k]!==ps[k])||['x','y','dx','dy','transform'].some(k=>child.hasAttribute(k)))fail(child,'text','line spans must keep one style and baseline');
      }
      const ls=getComputedStyle(line);
      if (line!==el && (line.hasAttribute('transform') || ls.transform!=='none')) fail(line,'transform','line transforms are unsupported');
      styleOf(line,matrix);
      if ((ls.stroke !== 'none' && parseFloat(ls.strokeWidth)>0) || !['normal','100%'].includes(ls.fontStretch) || ls.fontFeatureSettings !== 'normal' || ls.fontVariationSettings !== 'normal' || !['auto','alphabetic'].includes(ls.dominantBaseline)) fail(line,'text','unsupported text paint or font features');
      if (ls.textTransform !== 'none' || ls.textShadow !== 'none' || parseFloat(ls.webkitTextStrokeWidth) !== 0 || ls.fontKerning !== 'none' || ls.fontVariantLigatures !== 'none') fail(line,'text','unsupported text presentation');
      if ([el,line].some(n=>n.hasAttribute('rotate')||n.hasAttribute('textLength')||['x','y','dx','dy'].some(k=>/[, ]/.test(n.getAttribute(k)||'')))) fail(line,'text','per-character positioning unsupported');
      if(ls.fontFamily.replaceAll('"','')!=='VectorInter'||ls.fontWeight!=='400'||ls.fontStyle!=='normal'||ls.letterSpacing!=='normal'||!['normal','0px'].includes(ls.wordSpacing))fail(line,'font','exact VectorInter regular face required');
      const text=line.textContent;
      if (text.includes('${')) fail(line,'text','Roc interpolation syntax is unsupported');
      if (ls.textDecorationLine !== 'none') fail(line,'text','text decoration unsupported');
      if (text!==text.trim() || text.includes('  ') || line.getNumberOfChars()!==text.length) fail(line,'text','unsupported whitespace or addressable-character layout');
      if(!text||/[\r\n\t]/.test(text))fail(line,'text','one nonempty line required');
      if([...text].some(c=>!((c.codePointAt(0)>=32&&c.codePointAt(0)<=126)||c==='é')))fail(line,'text','profile accepts ASCII and é');
      const start=line.getStartPositionOfChar(0),length=line.getComputedTextLength();
      const alignment={start:'Start',middle:'Center',end:'End'}[ls.textAnchor];
      if(!alignment)fail(line,'text','unsupported anchor');
      const offset=alignment==='Center'?length/2:alignment==='End'?length:0;
      const origin=point(start.x+offset,start.y,matrix);
      const b=line.getBBox();
      labels.push({text,origin,align:alignment,size:Math.round(parseFloat(ls.fontSize)*matrix.a*750),color:color(line,ls.fill)});
      paint.push({label:true,el:line,box:[b.x*matrix.a+matrix.e,b.y*matrix.a+matrix.f,b.width*matrix.a,b.height*matrix.a]});
    }
  };
  visit(svg);
  let comparisons=0;
  for(let i=0;i<paint.length;i++)if(paint[i].label)for(let j=i+1;j<paint.length;j++)if(!paint[j].label){
    if(++comparisons>1000000)fail(svg,"budget","label paint-order work exceeded");
    const a=paint[i].box,b=paint[j].box;
    if(a[0]<b[0]+b[2]&&b[0]<a[0]+a[2]&&a[1]<b[1]+b[3]&&b[1]<a[1]+a[3])fail(paint[j].el,'order','later geometry overlaps an earlier label');
  }
  const width=Math.round(box.width*750),height=Math.round(box.height*750);
  for(const p of paths)for(const segment of p.segments)for(let i=1;i<segment.length;i+=2){
    const half=p.width/2;
    if(segment[i]-half<0||segment[i+1]-half<0||segment[i]+half>width||segment[i+1]+half>height)fail(svg,'geometry','geometry or stroke escapes viewBox');
  }
  for(const label of labels)if(!label.color||!Number.isSafeInteger(label.size)||label.size<=0||label.size>750000000||label.origin.some(n=>n<0))fail(svg,'text','invalid label geometry or paint');
  return {schema_version:1,width,height,background:[255,255,255],paths,labels};
}

export function rocModule(diagram) {
  const unit = value => `Layout.Unit.millipoints(${value})`;
  const point = (x,y) => `{ x: ${unit(x)}, y: ${unit(y)} }`;
  const color = rgb => `Color.srgb8({ red: ${rgb[0]}, green: ${rgb[1]}, blue: ${rgb[2]} })`;
  const lines=['## Generated by preparation/prepare.mjs; edit the source diagram instead.','import pdf.Color','import pdf.Layout','import pdf.Scene','','PreparedDiagram :: [].{','\tdrawing : {} -> Scene.Drawing','\tdrawing = |_| {',`\t\tvar $drawing = Scene.Drawing.empty.rectangle({ origin: ${point(0,0)}, size: { width: ${unit(diagram.width)}, height: ${unit(diagram.height)} } }, ${color(diagram.background)})`];
  for(const p of diagram.paths){
    let expression='Scene.PathBuilder.start';
    for(const s of p.segments){
      if(s[0]==='M')expression+=`.move_to(${point(s[1],s[2])})`;
      if(s[0]==='L')expression+=`.line_to(${point(s[1],s[2])})`;
      if(s[0]==='C')expression+=`.cubic_to({ control_1: ${point(s[1],s[2])}, control_2: ${point(s[3],s[4])}, end: ${point(s[5],s[6])} })`;
      if(s[0]==='Z')expression+='.close()';
    }
    lines.push(`\t\t$drawing = $drawing.path(${expression}.finish(), { fill: ${p.fill?`AuthorSolidFill(${color(p.fill)})`:'AuthorNoFill'}, stroke: ${p.stroke?`AuthorSolidStroke({ color: ${color(p.stroke)}, width: ${unit(p.width)} })`:'AuthorNoStroke'} })`);
  }
  for(const l of diagram.labels)lines.push(`\t\t$drawing = $drawing.text({ text: ${JSON.stringify(l.text)}, origin: ${point(...l.origin)}, size: ${unit(l.size)}, align: ${l.align}, color: ${color(l.color)} })`);
  lines.push('\t\t$drawing','\t}','}','');
  return lines.join('\n');
}

export async function browser() {
  if (process.version !== 'v23.9.0') throw new Error('Preparation requires Node v23.9.0');
  const chrome=await puppeteer.launch({headless:true, executablePath:process.env.VECTOR_CHROME || undefined, args:['--no-sandbox']});
  if (await chrome.version() !== 'Chrome/155.0.8059.79') { await chrome.close(); throw new Error('Preparation requires Chrome 155.0.8059.79 from the locked Puppeteer'); }
  return chrome;
}

async function main() {
  const args=process.argv.slice(2);
  const chrome=await browser();
  try{
    const page=await chrome.newPage();
    await page.setRequestInterception(true);
    page.on('request',request=>request.url().startsWith('data:')?request.continue():request.abort());
    const font=await fs.readFile(path.join(example,'fonts/Inter-Regular.ttf'));
    await page.setContent(`<style>body{margin:0}@font-face{font-family:VectorInter;src:url(data:font/ttf;base64,${font.toString('base64')})}</style>`);
    await page.evaluate(()=>document.fonts.load('16px VectorInter'));
    let svg;
    if(args[0]==='--svg')svg=await fs.readFile(args[1],'utf8');
    else{
      await page.addScriptTag({path:path.join(directory,'node_modules/mermaid/dist/mermaid.js')});
      const config=JSON.parse(await fs.readFile(path.join(directory,'mermaid.json'),'utf8'));
      const source=await fs.readFile(path.join(directory,'diagram.mmd'),'utf8');
      svg=await page.evaluate(async ({config,source})=>{mermaid.initialize({...config,startOnLoad:false});return (await mermaid.render('prepared-diagram',source)).svg;},{config,source});
      // Explicitly enlarge the viewport on its top/left for nonzero-origin
      // evidence. No Mermaid geometry or label is changed.
      svg=svg.replace(/viewBox="([^"]+)"/,(_,raw)=>{const [x,y,w,h]=raw.split(/\s+/).map(Number);return `viewBox="${x-12} ${y-8} ${w+24} ${h+16}"`;});
      await fs.writeFile(path.join(directory,'diagram.svg'),svg+'\n');
    }
    const resolved=await page.evaluate(resolveSvg,svg);
    const generated=rocModule(resolved);
    const output=args[0]==='--svg'?args[2]:path.join(example,'PreparedDiagram.roc');
    if(!output)throw new Error('usage: node prepare.mjs [--svg INPUT.svg OUTPUT.roc]');
    await fs.writeFile(output,generated);
    if(args[0]!=='--svg'){
      await fs.writeFile(path.join(directory,'resolved.json'),JSON.stringify(resolved,null,2)+'\n');
      await page.setViewport({width:Math.ceil(resolved.width/750),height:Math.ceil(resolved.height/750),deviceScaleFactor:1});
      await page.screenshot({path:path.join(directory,'reference.png'),clip:{x:0,y:0,width:resolved.width/750,height:resolved.height/750}});
      const pins={schema_version:1,node:process.version,browser:await chrome.version(),font_sha256:digest(font),inputs:{}};
      for(const name of ['diagram.mmd','mermaid.json','diagram.svg','resolved.json','reference.png','package-lock.json','prepare.mjs','test.mjs'])pins.inputs[name]=digest(await fs.readFile(path.join(directory,name)));
      pins.inputs['../PreparedDiagram.roc']=digest(generated);
      await fs.writeFile(path.join(directory,'provenance.json'),JSON.stringify(pins,null,2)+'\n');
    }
    console.log(`Prepared ${resolved.paths.length} paths and ${resolved.labels.length} Unicode labels`);
  }finally{await chrome.close();}
}
if(process.argv[1]===fileURLToPath(import.meta.url))main().catch(error=>{console.error(error.message);process.exitCode=1;});
