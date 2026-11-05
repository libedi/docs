#!/usr/bin/env node
// AC → Property → 테스트 → 실행 결과 사슬을 결정론적으로 대조한다. LLM이 판단하지 않는다.
// 리뷰어는 이 결과를 받아 "연결된 테스트가 정말 그 AC의 의미를 검증하는가"만 판단한다.
//
//   node spec-trace.mjs --spec <스펙 디렉터리> [--feature <이름>]
//                       [--tests <디렉터리>]... [--results <디렉터리>]...
//                       [--range <from-ref> <to-ref>] [--record <target>] [--json <파일>] [--strict]
//
//   --spec      requirements.md, design.md, tasks.md가 있는 디렉터리
//               (예: .kiro/specs/<SpecModuleKey>/01-<SpecDirectoryName>)
//   --feature   테스트 @Tag의 "Feature: <이름>". 생략하면 스펙 디렉터리 이름에서 앞의 "NN-"를 뺀 값
//   --tests     테스트 소스를 찾을 디렉터리 (기본: 저장소 전체에서 경로에 /src/test/ 가 있는 .java)
//   --results   JUnit XML 디렉터리 (기본: 저장소 전체의 build/test-results)
//   --range     이번 feature의 변경 범위. AC 번호만 적힌 표시(@DisplayName "(AC 4.1)", javadoc Validates)는
//               feature를 가리키지 않으므로 이 범위에서 바뀐 테스트 파일에서만 인정한다.
//               미표시 테스트 목록도 이 범위에서 뽑는다.
//   --record    리뷰 대상(예: feature). 범위를 <target>/start → 최신 done으로 잡고,
//               결과를 git-path review/<target>/trace-<최신 done>.json 으로 남긴다.
//   --strict    경고(연결 없는 AC, 테스트 없는 Property, 실패·미실행)도 종료 코드 1로 본다.
//
// 읽는 형식 (사내 Kiro 스펙 기준)
//   requirements.md  "### Requirement <N>: 제목" 아래 "#### Acceptance Criteria", 그 아래 줄 맨 앞의 "<n>. "
//                    (EARS 절마다 줄바꿈한 이어지는 줄은 들여쓰기로 같은 항목에 묶는다) → AC "<N>.<n>"
//                    본문이 "~~"로 시작하면 취소선으로 지운 AC(withdrawn): 번호는 차지하고 연결은 요구하지 않음
//   design.md        "### Property <N>: 제목" 절 안의 "**Validates: Requirements 4.1, 4.3**"
//                    재사용이면 "**Reuses: <테스트 클래스> (Feature: <이름>, Property 4, 11)**" (여럿이면 ;로 구분)
//   tasks.md         "- [x|-|~| ] <번호>. 제목" 아래 "_Requirements: 1.2, 1.3_" (대소문자 무관),
//                    "**Property <N>: …** - **Validates: Requirements …**", "STC 적용 제외"
//   테스트           @Tag("Feature: <이름>, Property <N>: …")   → Property 연결 (feature 명시)
//                    javadoc "**Validates: Requirements 1.3, 1.7**", @DisplayName/@Label "(AC 4.1, 4.4)"
//                                                              → AC 직접 연결 (--range 안의 파일만)
//                    javadoc "**Validates: Requirements 1.3 (Feature: <이름>)**"
//                                                              → feature를 담은 직접 연결 (범위와 무관, 그 feature일 때만)
//                    javadoc "**No-AC: <이유>**"      → AC와 직접 연결되지 않는 테스트 (표시 없음으로 세지 않음)
//                    클래스에 붙은 표시는 그 클래스의 모든 테스트 메서드에 적용한다.
//
// 종료 코드: 0 문제 없음, 1 구조 오류(없는 AC·Property 참조, AC를 하나도 못 읽음 등) 또는 --strict 경고, 2 사용법
// 의존성 없음 (Node.js 18+).
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, join, relative, resolve, sep } from 'node:path';

// ---------- 인자 ----------
const argv = process.argv.slice(2);
const opt = { tests: [], results: [], strict: false };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--spec') opt.spec = argv[++i];
  else if (a === '--feature') opt.feature = argv[++i];
  else if (a === '--tests') opt.tests.push(argv[++i]);
  else if (a === '--results') opt.results.push(argv[++i]);
  else if (a === '--range') { opt.from = argv[++i]; opt.to = argv[++i]; }
  else if (a === '--record') opt.record = argv[++i];
  else if (a === '--json') opt.json = argv[++i];
  else if (a === '--strict') opt.strict = true;
  else { console.error(`알 수 없는 인자: ${a}`); process.exit(2); }
}
if (!opt.spec) {
  console.error('usage: node spec-trace.mjs --spec <dir> [--feature f] [--tests d]... [--results d]... [--range from to] [--record target] [--json f] [--strict]');
  process.exit(2);
}

const git = (...a) => execFileSync('git', a, { cwd: top, stdio: ['ignore', 'pipe', 'pipe'] }).toString().trim();
const top = execFileSync('git', ['rev-parse', '--show-toplevel']).toString().trim();
const specDir = resolve(opt.spec);
const feature = opt.feature ?? basename(specDir).replace(/^\d+-/, '');
const acList = (s) => (String(s).match(/\d+\.\d+/g) ?? []);

const errors = [];
const warnings = [];
const err = (code, msg, extra = {}) => errors.push({ code, msg, ...extra });
const warn = (code, msg, extra = {}) => warnings.push({ code, msg, ...extra });

// 기록 위치와 범위는 파싱 전에 정한다. 파서가 낯선 소스에서 예외로 죽어도 결과 파일은 남긴다.
const ns = 'refs/worktree/review';
let latestDone = null;
if (opt.record) {
  let n = 0;
  while (true) { try { git('show-ref', '--verify', '-q', `${ns}/${opt.record}/done-${n + 1}`); n++; } catch { break; } }
  if (n > 0) latestDone = `done-${n}`;
  if (!opt.from && n > 0) { opt.from = `${ns}/${opt.record}/start`; opt.to = `${ns}/${opt.record}/${latestDone}`; }
}
let outPath = opt.json ? resolve(opt.json) : null;
if (opt.record) {
  const dir = resolve(top, git('rev-parse', '--git-path', `review/${opt.record}`));
  mkdirSync(dir, { recursive: true });
  outPath = join(dir, `trace-${latestDone ?? 'adhoc'}.json`);
}

// ---------- requirements.md ----------
function parseRequirements(text) {
  const acs = new Map(); // "N.n" -> {req, title, text}
  let req = null; let inAc = false; let cur = null;
  for (const line of text.split(/\r?\n/)) {
    const h = line.match(/^#{2,5}\s+Requirements?\s+(\d+)\b\s*[:.]?\s*(.*)$/i);
    if (h) { req = { n: h[1], title: h[2].trim() }; inAc = false; cur = null; continue; }
    if (/^#{2,6}\s+Acceptance Criteria\s*$/i.test(line)) { inAc = req !== null; cur = null; continue; }
    if (/^#{1,6}\s/.test(line)) { inAc = false; cur = null; continue; }
    if (!inAc) continue;
    const item = line.match(/^(\d+)\.\s+(.*)$/);
    if (item) {
      const id = `${req.n}.${item[1]}`;
      if (acs.has(id)) err('duplicate-ac', `requirements.md에 AC ${id}가 두 번 있습니다`);
      cur = { id, req: req.n, title: req.title, text: item[2].trim() };
      acs.set(id, cur);
    } else if (cur && /^\s+\S/.test(line)) {
      cur.text += ' ' + line.trim();
    } else if (line.trim() === '') {
      // 항목 사이 빈 줄은 무시
    } else {
      cur = null;
    }
  }
  for (const a of acs.values()) {
    a.text = a.text.replace(/\s{2,}/g, ' ');
    // 취소선으로 지운 AC: 번호는 차지하지만 태스크·테스트 연결을 요구하지 않는다
    a.withdrawn = a.text.startsWith('~~');
  }
  // 번호 건너뜀 (AC를 지우고 번호를 당기지 않았는지 사람이 보도록)
  const byReq = {};
  for (const a of acs.values()) (byReq[a.req] ??= []).push(Number(a.id.split('.')[1]));
  for (const [r, ns] of Object.entries(byReq)) {
    ns.sort((x, y) => x - y);
    ns.forEach((n, i) => { if (n !== i + 1) warn('ac-numbering-gap', `Requirement ${r}의 AC 번호가 ${i + 1}부터 연속되지 않습니다 (${ns.join(', ')})`); });
  }
  return acs;
}

// ---------- design.md ----------
function parseReuses(s) {
  return s.split(';').map((part) => {
    const m = part.trim().match(/^([A-Za-z_][\w.$]*)\s*(?:\(\s*Feature:\s*([^,)]+?)\s*,\s*Property\s+([\d,\s]+)\))?/);
    if (!m) return null;
    return { cls: m[1], feature: m[2]?.trim() ?? null, props: (m[3]?.match(/\d+/g) ?? []) };
  }).filter(Boolean);
}
function parseDesign(text) {
  const props = new Map(); // "N" -> {n, title, validates:[], reuses:[]}
  let cur = null; let level = 0;
  for (const line of text.split(/\r?\n/)) {
    const h = line.match(/^(#{2,5})\s+Property\s+(\d+)\s*:\s*(.*)$/i);
    if (h) {
      if (props.has(h[2])) err('duplicate-property', `design.md에 Property ${h[2]}가 두 번 있습니다`);
      cur = { n: h[2], title: h[3].trim(), validates: [], reuses: [] };
      level = h[1].length; props.set(h[2], cur); continue;
    }
    const other = line.match(/^(#{1,6})\s/);
    if (other && other[1].length <= level) { cur = null; continue; }
    if (!cur) continue;
    const v = line.match(/\*\*Validates:\s*Requirements?\s+([^*]+)\*\*/i);
    if (v) cur.validates.push(...acList(v[1]));
    const r = line.match(/\*\*Reuses:\s*([^*]+)\*\*/i);
    if (r) cur.reuses.push(...parseReuses(r[1]));
  }
  return props;
}

// ---------- tasks.md ----------
function parseTasks(text) {
  const tasks = []; let cur = null;
  for (const line of text.split(/\r?\n/)) {
    const t = line.match(/^(\s*)- \[(.)\](\*?)\s+(\d+(?:\.\d+)*)\.?\s+(.*)$/);
    if (t) {
      if (t[3]) warn('optional-task-marker', `tasks.md ${t[4]}가 선택 태스크(\`- [ ]*\`)로 표시돼 있습니다. 사내 형식에서는 쓰지 않는 표시라 확인이 필요합니다`);
      const indent = t[1].length;
      const parent = [...tasks].reverse().find((x) => x.indent < indent) ?? null;
      cur = { id: t[4], status: t[2], title: t[5].trim(), optional: t[3] === '*', indent, requirements: [], properties: [],
        stcExcluded: parent?.stcExcluded ?? false };
      tasks.push(cur); continue;
    }
    if (!cur) continue;
    if (/STC\s*적용\s*제외/.test(line)) cur.stcExcluded = true;
    const r = line.match(/_requirements:\s*([^_]+)_/i);
    if (r) cur.requirements.push(...acList(r[1]));
    const p = line.match(/\*\*Property\s+(\d+)\s*:[^*]*\*\*.*?\*\*Validates:\s*Requirements?\s+([^*]+)\*\*/i);
    if (p) cur.properties.push({ n: p[1], validates: acList(p[2]) });
  }
  return tasks;
}

// ---------- 테스트 소스 ----------
const TEST_ANNOS = new Set(['Test', 'Property', 'Example', 'ParameterizedTest', 'RepeatedTest', 'TestFactory', 'TestTemplate']);
const SKIP_DIRS = new Set(['.git', 'build', 'node_modules', '.gradle', '.worktrees', 'out', 'target', '.idea']);
function walk(dir, pred, acc = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    let st; try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) { if (!SKIP_DIRS.has(name)) walk(p, pred, acc); }
    else if (pred(p)) acc.push(p);
  }
  return acc;
}
function readAnnotation(s) {
  // s는 '@'로 시작. 이름과 괄호 인자(균형)를 읽는다. 균형이 안 맞으면 null
  const m = s.match(/^@([\w.]+)\s*/);
  if (!m) return null;
  let i = m[0].length; let args = '';
  if (s[i] === '(') {
    let depth = 0; let inStr = false; let j = i;
    for (; j < s.length; j++) {
      const c = s[j];
      if (inStr) { if (c === '\\') j++; else if (c === '"') inStr = false; continue; }
      if (c === '"') inStr = true; else if (c === '(') depth++; else if (c === ')') { depth--; if (depth === 0) break; }
    }
    if (depth !== 0) return null;
    args = s.slice(i + 1, j); i = j + 1;
  }
  return { name: m[1].split('.').pop(), args, rest: s.slice(i).trim() };
}
const strings = (s) => [...s.matchAll(/"((?:\\.|[^"\\])*)"/g)].map((x) => x[1]);
function markersOf(doc, annos) {
  const mk = { props: [], acs: [], acFeature: null, display: null, noAc: false };
  if (doc) {
    const v = doc.match(/Validates:\s*Requirements?\s+([\d.,\s]+)(?:\(\s*Feature:\s*([^)]+?)\s*\))?/i);
    if (v) { mk.acs.push(...acList(v[1])); mk.acFeature = v[2]?.trim() ?? null; }
    if (/No-AC:/i.test(doc)) mk.noAc = true;
  }
  for (const a of annos) {
    if (a.name === 'Tag' || a.name === 'Tags') {
      for (const s of strings(a.args)) {
        const m = s.match(/Feature:\s*([^,]+?)\s*,\s*Property\s+(\d+)/);
        if (m) mk.props.push({ feature: m[1].trim(), n: m[2] });
      }
    }
    if (a.name === 'DisplayName' || a.name === 'Label') {
      const s = strings(a.args)[0] ?? '';
      mk.display = s;
      for (const m of s.matchAll(/\bAC[-\s]*(\d+\.\d+(?:\s*[,/]\s*(?:AC[-\s]*)?\d+\.\d+)*)/g)) mk.acs.push(...acList(m[1]));
    }
  }
  return mk;
}
function stripCode(line, state) {
  // 문자열·문자 리터럴·텍스트 블록·주석을 지운 코드 (중괄호 세기용)
  let out = ''; let i = 0;
  while (i < line.length) {
    if (state.textBlock) { const e = line.indexOf('"""', i); if (e < 0) return out; state.textBlock = false; i = e + 3; continue; }
    if (state.comment) { const e = line.indexOf('*/', i); if (e < 0) return out; state.comment = false; i = e + 2; continue; }
    if (line.startsWith('"""', i)) { state.textBlock = true; i += 3; continue; }
    if (line.startsWith('/*', i)) { state.comment = true; i += 2; continue; }
    if (line.startsWith('//', i)) return out;
    const c = line[i];
    if (c === '"' || c === '\'') { let j = i + 1; while (j < line.length && line[j] !== c) { if (line[j] === '\\') j++; j++; } i = j + 1; continue; }
    out += c; i++;
  }
  return out;
}
function parseJava(text, file) {
  const pkg = text.match(/^\s*package\s+([\w.]+)\s*;/m)?.[1] ?? '';
  const classes = []; const methods = [];
  const stack = []; let depth = 0; const state = { textBlock: false, comment: false };
  let doc = null; let docBuf = null; let annos = []; let annoBuf = null;
  const lines = text.split(/\r?\n/);
  for (const raw of lines) {
    const t = raw.trim();
    let handledDecl = false;
    if (!state.textBlock && !state.comment) {
      if (docBuf !== null) { docBuf += '\n' + t; if (t.includes('*/')) { doc = docBuf; docBuf = null; } continue; }
      if (t.startsWith('/**')) { if (t.indexOf('*/', 3) >= 0) doc = t; else docBuf = t; continue; }
      let rest = t;
      if (annoBuf !== null) { annoBuf += ' ' + t; const a = readAnnotation(annoBuf); if (!a) continue; annos.push(a); annoBuf = null; rest = a.rest; }
      while (rest.startsWith('@') && !/^@interface\b/.test(rest)) {
        const a = readAnnotation(rest);
        if (!a) { annoBuf = rest; rest = ''; break; }
        annos.push(a); rest = a.rest;
      }
      if (rest && !rest.startsWith('//') && !rest.startsWith('/*') && !rest.startsWith('*')) {
        const cd = rest.replace(/"(?:\\.|[^"\\])*"/g, '""').match(/\b(class|interface|enum|record)\s+([A-Za-z_]\w*)/);
        const isTest = annos.some((a) => TEST_ANNOS.has(a.name));
        if (cd && !isTest) {
          const parent = stack[stack.length - 1];
          const fqcn = parent ? `${parent.fqcn}$${cd[2]}` : (pkg ? `${pkg}.${cd[2]}` : cd[2]);
          const c = { fqcn, file, markers: markersOf(doc, annos), openDepth: depth, opened: false };
          classes.push(c); stack.push(c); handledDecl = true;
        } else if (isTest) {
          const mm = rest.match(/([A-Za-z_]\w*)\s*\(/);
          if (mm && stack.length) {
            methods.push({ cls: stack[stack.length - 1].fqcn, name: mm[1], file, markers: markersOf(doc, annos),
              kind: annos.find((a) => TEST_ANNOS.has(a.name)).name });
            handledDecl = true;
          }
        }
        if (handledDecl || !isTest) { doc = null; annos = []; }
      }
    }
    const code = stripCode(raw, state);
    for (const c of code) {
      if (c === '{') { depth++; const top = stack[stack.length - 1]; if (top && !top.opened && depth > top.openDepth) top.opened = true; }
      else if (c === '}') { depth--; while (stack.length && stack[stack.length - 1].opened && depth <= stack[stack.length - 1].openDepth) stack.pop(); }
    }
  }
  return { classes, methods };
}

// ---------- JUnit XML ----------
const unxml = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, '\'').replace(/&amp;/g, '&');
function parseResults(files) {
  const byClass = new Map();
  for (const f of files) {
    const x = readFileSync(f, 'utf8');
    for (const m of x.matchAll(/<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g)) {
      const attrs = Object.fromEntries([...m[1].matchAll(/(\w+)="([^"]*)"/g)].map((a) => [a[1], unxml(a[2])]));
      const body = m[3] ?? '';
      const status = /<(failure|error)\b/.test(body) ? 'failed' : /<skipped\b/.test(body) ? 'skipped' : 'passed';
      if (!byClass.has(attrs.classname)) byClass.set(attrs.classname, []);
      byClass.get(attrs.classname).push({ name: attrs.name ?? '', status });
    }
  }
  return byClass;
}
const norm = (n) => n.replace(/\(.*$/, '').replace(/\[.*$/, '').trim();
function resultOf(method, results, haveResults) {
  if (!haveResults) return 'unknown';
  const cases = (results.get(method.cls) ?? []).filter((c) => {
    const n = norm(c.name);
    return n === method.name || c.name === method.name || (method.display && (c.name === method.display || n === method.display));
  });
  if (cases.length === 0) return 'not-run';
  if (cases.some((c) => c.status === 'failed')) return 'failed';
  if (cases.every((c) => c.status === 'skipped')) return 'skipped';
  return 'passed';
}
// 연결된 테스트들의 상태를 하나로 모은다. 하나라도 통과하지 못했으면 통과로 보지 않는다.
const aggregate = (statuses) => {
  if (statuses.length === 0) return 'none';
  if (statuses.includes('failed')) return 'failed';
  if (statuses.every((s) => s === 'unknown')) return 'unknown';
  const passed = statuses.filter((s) => s === 'passed').length;
  if (passed === statuses.length) return 'passed';
  if (passed > 0) return 'partial';          // 일부 통과, 일부 미실행·건너뜀
  if (statuses.includes('not-run')) return 'not-run';
  return 'skipped';
};

// ---------- 실행 ----------
try {
for (const f of ['requirements.md', 'design.md', 'tasks.md']) {
  if (!existsSync(join(specDir, f))) { err('missing-spec-file', `${f}가 없습니다: ${specDir}`); }
}
const read = (f) => (existsSync(join(specDir, f)) ? readFileSync(join(specDir, f), 'utf8') : '');
const acs = parseRequirements(read('requirements.md'));
const props = parseDesign(read('design.md'));
const tasks = parseTasks(read('tasks.md'));
if (acs.size === 0) err('no-ac-parsed', 'requirements.md에서 AC를 하나도 읽지 못했습니다. 형식이 바뀌었는지 확인하세요 (대조 결과를 믿으면 안 됨)');
// AC를 못 읽었으면 AC 참조 오류는 모두 같은 원인의 연쇄라 생략한다
const acKnown = (a) => acs.size === 0 || acs.has(a);

// 범위 (--record면 <target>/start → 최신 done. 위에서 정함)
let changedTests = null;
if (opt.from && opt.to) {
  changedTests = new Set(git('diff', '--name-only', opt.from, opt.to).split('\n').filter((p) => p.includes('/src/test/') && p.endsWith('.java')));
}

// 테스트 소스
const testRoots = opt.tests.length ? opt.tests.map((d) => resolve(d)) : [top];
const javaFiles = testRoots.flatMap((d) => walk(d, (p) => p.endsWith('.java') && p.split(sep).join('/').includes('/src/test/')));
const allClasses = []; const allMethods = [];
for (const f of javaFiles) {
  const { classes, methods } = parseJava(readFileSync(f, 'utf8'), relative(top, f).split(sep).join('/'));
  allClasses.push(...classes); allMethods.push(...methods);
}
const classByFqcn = new Map(allClasses.map((c) => [c.fqcn, c]));
for (const m of allMethods) {
  const c = classByFqcn.get(m.cls);
  m.props = [...m.markers.props, ...(c?.markers.props ?? [])];
  m.acs = [...new Set([...m.markers.acs, ...(c?.markers.acs ?? [])])];
  m.display = m.markers.display;
  m.noAc = m.markers.noAc || (c?.markers.noAc ?? false);
  m.acFeature = m.markers.acs.length ? m.markers.acFeature : (c?.markers.acFeature ?? null);
  m.inRange = changedTests ? changedTests.has(m.file) : true;
}

// 실행 결과
let xmlFiles = [];
if (opt.results.length) {
  xmlFiles = opt.results.map((d) => resolve(d)).flatMap((d) => (existsSync(d) ? walk(d, (p) => /TEST-.*\.xml$/.test(p)) : []));
}
else {
  const findResults = (dir, acc = []) => {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name); let st; try { st = statSync(p); } catch { continue; }
      if (!st.isDirectory()) continue;
      if (name === 'test-results' && basename(dir) === 'build') acc.push(...walkAll(p));
      else if (!['.git', 'node_modules', '.gradle', '.worktrees', 'src'].includes(name)) findResults(p, acc);
    }
    return acc;
  };
  const walkAll = (d) => { const acc = []; const go = (x) => { for (const n of readdirSync(x)) { const p = join(x, n); const s = statSync(p); if (s.isDirectory()) go(p); else if (/TEST-.*\.xml$/.test(n)) acc.push(p); } }; go(d); return acc; };
  xmlFiles = findResults(top);
}
const results = parseResults(xmlFiles);
const haveResults = xmlFiles.length > 0;
if (!haveResults) warn('no-results', '테스트 결과 XML을 찾지 못했습니다. 연결만 대조하고 통과 여부는 보지 않았습니다');
for (const m of allMethods) m.result = resultOf(m, results, haveResults);

// Property → 테스트
const tagIndex = new Map();
for (const m of allMethods) for (const p of m.props) {
  const k = `${p.feature}#${p.n}`; if (!tagIndex.has(k)) tagIndex.set(k, []); tagIndex.get(k).push(m);
}
const simpleName = (fqcn) => fqcn.split('.').pop().split('$').pop();
const propertyRows = [];
for (const p of props.values()) {
  for (const a of p.validates) {
    if (!acKnown(a)) err('unknown-ac-in-design', `design.md Property ${p.n}가 없는 AC ${a}를 가리킵니다`);
    else if (acs.get(a)?.withdrawn) warn('withdrawn-ac-referenced', `design.md Property ${p.n}가 취소선으로 지운 AC ${a}를 가리킵니다`);
  }
  if (p.validates.length === 0) warn('property-without-validates', `design.md Property ${p.n}에 Validates가 없습니다`);
  const own = tagIndex.get(`${feature}#${p.n}`) ?? [];
  const reused = [];
  for (const r of p.reuses) {
    const inClass = allMethods.filter((m) => m.cls === r.cls || simpleName(m.cls) === r.cls || m.cls.endsWith(`.${r.cls}`));
    if (inClass.length === 0) { err('reuse-class-missing', `Property ${p.n}의 Reuses 클래스 ${r.cls}를 테스트 소스에서 찾지 못했습니다`); continue; }
    const picked = r.props.length
      ? inClass.filter((m) => m.props.some((q) => r.props.includes(q.n) && (!r.feature || q.feature === r.feature)))
      : inClass;
    if (r.props.length) for (const n of r.props) {
      if (!picked.some((m) => m.props.some((q) => q.n === n && (!r.feature || q.feature === r.feature)))) {
        err('reuse-property-missing', `Property ${p.n}의 Reuses ${r.cls} Property ${n}에 해당하는 테스트가 없습니다`);
      }
    }
    reused.push(...picked);
  }
  if (own.length === 0 && p.reuses.length === 0) warn('property-untested', `Property ${p.n}에 연결된 테스트가 없습니다 (@Tag "Feature: ${feature}, Property ${p.n}" 또는 Reuses 필요)`);
  const linked = [...own, ...reused];
  const status = aggregate(linked.map((m) => m.result));
  if (['failed', 'partial', 'not-run', 'skipped'].includes(status)) warn(`property-${status}`, `Property ${p.n}의 테스트 상태: ${status}`);
  if (p.reuses.length) warn('reuse-needs-review', `Property ${p.n}는 기존 테스트를 재사용합니다. 재사용한 속성이 AC ${p.validates.join(', ')}의 의미까지 덮는지는 리뷰어가 판단합니다`);
  propertyRows.push({ property: p.n, title: p.title, validates: p.validates, reuses: p.reuses,
    tests: linked.map((m) => ({ test: `${m.cls}#${m.name}`, file: m.file, result: m.result, via: own.includes(m) ? 'tag' : 'reuse' })), status });
}
// 이 feature 태그인데 design에 없는 Property
for (const [k, ms] of tagIndex) {
  const [f, n] = k.split('#');
  if (f === feature && !props.has(n)) for (const m of ms) err('unknown-property-in-test', `${m.cls}#${m.name}의 @Tag가 design.md에 없는 Property ${n}를 가리킵니다`, { file: m.file });
}

// tasks 대조
const acInTasks = new Map();
for (const t of tasks) {
  for (const a of t.requirements) {
    if (!acKnown(a)) err('unknown-ac-in-tasks', `tasks.md ${t.id}가 없는 AC ${a}를 가리킵니다`);
    else if (acs.get(a)?.withdrawn) warn('withdrawn-ac-referenced', `tasks.md ${t.id}가 취소선으로 지운 AC ${a}를 가리킵니다`);
    if (!acInTasks.has(a)) acInTasks.set(a, []);
    acInTasks.get(a).push(t);
  }
  for (const tp of t.properties) {
    const dp = props.get(tp.n);
    if (!dp) err('unknown-property-in-tasks', `tasks.md ${t.id}가 design.md에 없는 Property ${tp.n}를 가리킵니다`);
    else if ([...tp.validates].sort().join() !== [...dp.validates].sort().join()) {
      warn('task-property-mismatch', `tasks.md ${t.id}의 Property ${tp.n} Validates(${tp.validates.join(', ')})가 design.md(${dp.validates.join(', ')})와 다릅니다`);
    }
  }
}

// AC별 연결
const acRows = [];
for (const a of acs.values()) {
  const viaProps = propertyRows.filter((r) => r.validates.includes(a.id));
  // AC 번호만 있는 표시는 이번 변경 파일에서만, feature를 담은 표시는 그 feature일 때만 인정
  const direct = allMethods.filter((m) => m.acs.includes(a.id) && (m.acFeature ? m.acFeature === feature : m.inRange));
  const ts = acInTasks.get(a.id) ?? [];
  if (a.withdrawn) {
    if (direct.length) warn('withdrawn-ac-referenced', `취소선으로 지운 AC ${a.id}를 테스트 ${direct.length}개가 가리킵니다`);
    acRows.push({ ac: a.id, requirement: a.req, text: a.text, tasks: ts.map((t) => t.id), withdrawn: true, stc_excluded: false,
      properties: viaProps.map((r) => r.property),
      direct_tests: direct.map((m) => ({ test: `${m.cls}#${m.name}`, file: m.file, result: m.result })), status: 'withdrawn' });
    continue;
  }
  if (ts.length === 0) err('ac-not-in-tasks', `AC ${a.id}를 가리키는 태스크가 없습니다`);
  const exempt = ts.length > 0 && ts.every((t) => t.stcExcluded);
  const statuses = [...viaProps.flatMap((r) => r.tests.map((x) => x.result)), ...direct.map((m) => m.result)];
  let status = aggregate(statuses);
  if (status === 'none') status = exempt ? 'exempt' : 'unlinked';
  if (status === 'unlinked') warn('ac-unlinked', `AC ${a.id}에 연결된 테스트가 없습니다 (Property Validates, 또는 이번 변경 테스트의 AC 표시)`);
  else if (['failed', 'partial', 'not-run', 'skipped'].includes(status)) warn(`ac-${status}`, `AC ${a.id}에 연결된 테스트 상태: ${status}`);
  acRows.push({ ac: a.id, requirement: a.req, text: a.text, tasks: ts.map((t) => t.id), stc_excluded: exempt,
    properties: viaProps.map((r) => r.property),
    direct_tests: direct.map((m) => ({ test: `${m.cls}#${m.name}`, file: m.file, result: m.result })), status });
}

// 이번 변경에서 표시 없는 테스트
const unmarked = changedTests
  ? allMethods.filter((m) => m.inRange && m.props.length === 0 && m.acs.length === 0 && !m.noAc).map((m) => ({ test: `${m.cls}#${m.name}`, file: m.file }))
  : null;
if (unmarked?.length) warn('unmarked-tests', `이번 변경 테스트 중 AC·Property 표시가 없는 것이 ${unmarked.length}개 있습니다`);

// ---------- 출력 ----------
const report = {
  at: new Date().toISOString(), feature, spec: relative(top, specDir) || '.',
  range: changedTests ? { from: opt.from, to: opt.to } : null,
  sources: { test_files: javaFiles.length, test_methods: allMethods.length, result_files: xmlFiles.length },
  summary: {
    acs: acRows.length,
    verified: acRows.filter((r) => r.status === 'passed').length,
    partial: acRows.filter((r) => r.status === 'partial').length,
    withdrawn: acRows.filter((r) => r.status === 'withdrawn').length,
    exempt: acRows.filter((r) => r.status === 'exempt').length,
    unlinked: acRows.filter((r) => r.status === 'unlinked').length,
    failed: acRows.filter((r) => r.status === 'failed').length,
    not_run: acRows.filter((r) => r.status === 'not-run').length,
    properties: propertyRows.length,
    properties_untested: propertyRows.filter((r) => r.tests.length === 0 && r.reuses.length === 0).length,
    errors: errors.length, warnings: warnings.length,
  },
  errors, warnings, acs: acRows, properties: propertyRows, unmarked_tests: unmarked,
};

const icon = { passed: '통과', failed: '실패', partial: '일부 미실행', 'not-run': '미실행', skipped: '건너뜀', unknown: '결과 없음', unlinked: '연결 없음', exempt: 'STC 제외', withdrawn: '철회' };
console.log(`feature=${feature}  AC ${report.summary.acs}개, Property ${report.summary.properties}개, 테스트 메서드 ${allMethods.length}개, 결과 파일 ${xmlFiles.length}개`);
for (const r of acRows) {
  const via = [...r.properties.map((p) => `P${p}`), ...(r.direct_tests.length ? [`직접 ${r.direct_tests.length}`] : [])].join(', ');
  console.log(`  AC ${r.ac.padEnd(5)} ${(icon[r.status] ?? r.status).padEnd(6)} ${via}`);
}
if (unmarked?.length) { console.log('표시 없는 테스트 (이번 변경):'); for (const u of unmarked) console.log(`  ${u.test}`); }
for (const e of errors) console.log(`오류 [${e.code}] ${e.msg}`);
for (const w of warnings) console.log(`경고 [${w.code}] ${w.msg}`);

if (outPath) { writeFileSync(outPath, JSON.stringify(report, null, 2)); console.log(`기록: ${relative(top, outPath) || outPath}`); }

const strictFail = opt.strict && warnings.some((w) => /^(ac-unlinked|ac-failed|ac-partial|ac-not-run|property-untested|property-failed|property-partial|property-not-run)$/.test(w.code));
process.exit(errors.length || strictFail ? 1 : 0);
} catch (e) {
  // 예외로 멈춰도 결과 파일을 남긴다. 리뷰어는 이 오류를 findings로 옮기고 나머지 항목(FR-2~4)은 계속 본다.
  const crash = { code: 'crash', msg: `spec-trace가 예외로 멈췄습니다: ${e?.message ?? e}`, at: String(e?.stack ?? '').split('\n')[1]?.trim() ?? '' };
  const report = { at: new Date().toISOString(), feature, spec: relative(top, specDir) || '.', crashed: true,
    summary: { errors: errors.length + 1, warnings: warnings.length }, errors: [...errors, crash], warnings,
    acs: [], properties: [], unmarked_tests: null };
  console.log(`오류 [crash] ${crash.msg} (${crash.at})`);
  if (outPath) { writeFileSync(outPath, JSON.stringify(report, null, 2)); console.log(`기록: ${relative(top, outPath) || outPath}`); }
  process.exit(1);
}
