#!/usr/bin/env node
// 리뷰어 평가 채점. 정답(expected.json)과 리뷰어 findings를 기계적으로 비교한다. LLM이 채점하지 않는다.
//
//   node eval-score.mjs --cases <cases-dir> [--tag <reviewer-tag>] [--tolerance 3]
//                       [--baseline <result.json>] [--out <result.json>]
//
// 사례마다 git-path review/eval-<사례>/findings-1[.<tag>].json 을 읽는다.
// 매칭 규칙: check가 같고, 파일 경로가 한쪽의 접미사이고, 줄 번호가 정답 범위 ± tolerance 안이면 같은 지적.
//   - detected   blocker/major로 정답을 맞힌 것 (recall의 분자)
//   - uncertain  question으로 정답 위치를 짚은 것 (참고용)
//   - false_pos  어떤 정답과도 맞지 않는 blocker/major (버그 없는 사례 포함)
//   - noise      맞지 않는 minor/question
// 버그 없는 사례에서 나온 false_pos가 "따르면 해로운 지적"의 후보다.
// 오탐으로 집계된 지적이 실제 문제라면 expected.json에 추가한다.
// 의존성 없음 (Node.js 18+).
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => (a.startsWith('--') ? [...acc, [a.slice(2), all[i + 1]]] : acc), []),
);
if (!args.cases) {
  console.error('usage: node eval-score.mjs --cases <dir> [--tag t] [--tolerance 3] [--baseline f] [--out f]');
  process.exit(2);
}
const tol = Number(args.tolerance ?? 3);
const tag = args.tag ?? '';

const top = execFileSync('git', ['rev-parse', '--show-toplevel']).toString().trim();
const reviewDir = resolve(top, execFileSync('git', ['rev-parse', '--git-path', 'review'], { cwd: top }).toString().trim());

const parseLoc = (loc = '') => {
  const m = String(loc).match(/^(.*?)(?::(\d+)(?:-(\d+))?)?$/);
  return { file: m[1], line: m[2] ? Number(m[2]) : null };
};
const sameFile = (a, b) => !!a && !!b && (a.endsWith(b) || b.endsWith(a));
const matches = (exp, f) => {
  if (exp.check !== f.check) return false;
  const loc = parseLoc(f.location);
  if (!sameFile(loc.file, exp.file)) return false;
  const [lo, hi] = exp.lines ?? (exp.line != null ? [exp.line, exp.line] : [null, null]);
  if (lo == null || loc.line == null) return true;
  return loc.line >= lo - tol && loc.line <= hi + tol;
};

const cases = [];
for (const name of readdirSync(args.cases).sort()) {
  const dir = join(args.cases, name);
  if (!statSync(dir).isDirectory() || !existsSync(join(dir, 'expected.json'))) continue;
  const expected = JSON.parse(readFileSync(join(dir, 'expected.json'), 'utf8')).findings ?? [];
  const fpath = join(reviewDir, `eval-${name}`, `findings-1${tag ? `.${tag}` : ''}.json`);
  if (!existsSync(fpath)) {
    cases.push({ case: name, status: 'not-run', expected: expected.length });
    continue;
  }
  const findings = JSON.parse(readFileSync(fpath, 'utf8')).findings ?? [];
  const used = new Set();
  let detected = 0, uncertain = 0;
  const missed = [];
  for (const exp of expected) {
    const strong = findings.findIndex((f, i) => !used.has(i) && ['blocker', 'major'].includes(f.severity) && matches(exp, f));
    if (strong >= 0) { used.add(strong); detected++; continue; }
    const weak = findings.findIndex((f, i) => !used.has(i) && f.severity === 'question' && matches(exp, f));
    if (weak >= 0) { used.add(weak); uncertain++; }
    missed.push(exp);
  }
  const rest = findings.filter((_, i) => !used.has(i));
  const falsePos = rest.filter((f) => ['blocker', 'major'].includes(f.severity));
  const noise = rest.length - falsePos.length;
  cases.push({ case: name, status: 'scored', clean: expected.length === 0, expected: expected.length, detected, uncertain,
    missed, false_positives: falsePos, noise });
}

const scored = cases.filter((c) => c.status === 'scored');
const sum = (k) => scored.reduce((s, c) => s + (typeof c[k] === 'number' ? c[k] : c[k].length), 0);
const totals = {
  cases: cases.length,
  not_run: cases.length - scored.length,
  expected: sum('expected'),
  detected: sum('detected'),
  uncertain: sum('uncertain'),
  false_positives: sum('false_positives'),
  noise: sum('noise'),
  clean_cases: scored.filter((c) => c.clean).length,
  clean_with_false_positive: scored.filter((c) => c.clean && c.false_positives.length > 0).length,
};
totals.recall = totals.expected ? Number((totals.detected / totals.expected).toFixed(3)) : null;

const result = { at: new Date().toISOString(), tag: tag || null, tolerance: tol, totals, cases };

for (const c of cases) {
  if (c.status !== 'scored') { console.log(`${c.case}: 실행 안 됨 (findings 없음)`); continue; }
  console.log(`${c.case}: 정답 ${c.expected}, 발견 ${c.detected}, 질문 ${c.uncertain}, 오탐 ${c.false_positives.length}, 노이즈 ${c.noise}${c.clean ? ' (버그 없는 사례)' : ''}`);
}
console.log(`합계: recall ${totals.recall ?? '-'} (${totals.detected}/${totals.expected}), 오탐 ${totals.false_positives}, 버그 없는 사례 중 오탐 발생 ${totals.clean_with_false_positive}/${totals.clean_cases}, 미실행 ${totals.not_run}`);

if (args.baseline && existsSync(args.baseline)) {
  const b = JSON.parse(readFileSync(args.baseline, 'utf8')).totals;
  const d = (x, y) => (x == null || y == null ? '-' : (x - y > 0 ? '+' : '') + Number((x - y).toFixed(3)));
  console.log(`기준 대비: recall ${d(totals.recall, b.recall)}, 오탐 ${d(totals.false_positives, b.false_positives)}`);
  const better = totals.recall >= b.recall && totals.false_positives <= b.false_positives
    && (totals.recall > b.recall || totals.false_positives < b.false_positives);
  console.log(better ? '판정: 개선 (채택 가능)' : '판정: 개선 아님 (기존 유지)');
}
if (args.out) writeFileSync(args.out, JSON.stringify(result, null, 2));
