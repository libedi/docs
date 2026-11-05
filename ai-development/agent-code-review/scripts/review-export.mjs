#!/usr/bin/env node
// review-cleanup.sh로 지우기 전에 지적과 판정을 한 줄씩 남기고, 항목별 집계를 출력한다.
//
//   node review-export.mjs [out.jsonl] [--include-eval]
//
// out을 생략하면 메인 저장소 git 디렉터리의 review-metrics.jsonl(git rev-parse --git-common-dir)에 쌓는다.
// 워크트리를 지워도 남는 위치다.
//
// 줄 형식: {exported_at, branch, target, round, reviewer, index, check, source, severity, origin, resolution}
//   source가 "trace"면 spec-trace.mjs가 낸 사실을 리뷰어가 옮긴 지적이다. 리뷰어 판단의 채택률과 섞지 않으려고
//   집계에서는 "<check>(trace)"로 따로 센다.
//   reviewer는 태그 없는 기본 리뷰어면 "primary", 비교 리뷰어면 그 태그
// 집계 (기본 리뷰어 기준)
//   - 항목(check)별 지적 수와 판정 분포, 채택률 = fixed ÷ 판정된 지적
//   - 대상별 회차 수와 통과 여부 (마지막 회차에 이번 변경의 blocker/major가 없으면 통과)
// 의존성 없음 (Node.js 18+).
import { execFileSync } from 'node:child_process';
import { appendFileSync, existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const includeEval = process.argv.includes('--include-eval');
const outArg = process.argv.slice(2).find((a) => !a.startsWith('--'));

const top = execFileSync('git', ['rev-parse', '--show-toplevel']).toString().trim();
const git = (...a) => execFileSync('git', a, { cwd: top }).toString().trim();
const out = outArg ?? resolve(top, git('rev-parse', '--git-common-dir'), 'review-metrics.jsonl');
const reviewDir = resolve(top, git('rev-parse', '--git-path', 'review'));
const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
const now = new Date().toISOString();
if (!existsSync(reviewDir)) { console.log('리뷰 기록이 없습니다'); process.exit(0); }

const byCheck = {};
const byTarget = [];
const lines = [];
for (const target of readdirSync(reviewDir).sort()) {
  if (!includeEval && target.startsWith('eval-')) continue;
  const dir = join(reviewDir, target);
  const res = new Map();
  if (existsSync(join(dir, 'resolutions.jsonl'))) {
    for (const l of readFileSync(join(dir, 'resolutions.jsonl'), 'utf8').split('\n').filter(Boolean)) {
      const r = JSON.parse(l);
      res.set(`${r.round}:${r.index}`, r.resolution);
    }
  }
  let rounds = 0, lastPrimary = null;
  for (const f of readdirSync(dir).filter((n) => /^findings-\d+(\.[\w-]+)?\.json$/.test(n))) {
    const [, round, tag] = f.match(/^findings-(\d+)(?:\.([\w-]+))?\.json$/);
    const reviewer = tag ?? 'primary';
    const findings = JSON.parse(readFileSync(join(dir, f), 'utf8')).findings ?? [];
    if (reviewer === 'primary' && Number(round) >= rounds) { rounds = Number(round); lastPrimary = findings; }
    findings.forEach((x, index) => {
      const resolution = reviewer === 'primary' ? res.get(`${round}:${index}`) ?? null : null;
      lines.push({ exported_at: now, branch, target, round: Number(round), reviewer, index,
        check: x.check, source: x.source ?? null, severity: x.severity, origin: x.origin ?? null, resolution });
      if (reviewer !== 'primary') return;
      const key = x.source === 'trace' ? `${x.check}(trace)` : x.check;
      const c = (byCheck[key] ??= { total: 0, fixed: 0, wrong: 0, intentional: 0, minor: 0, harmful: 0, unresolved: 0 });
      c.total++;
      c[resolution ?? 'unresolved']++;
    });
  }
  const passed = lastPrimary === null ? null
    : !lastPrimary.some((x) => ['blocker', 'major'].includes(x.severity) && x.origin !== 'pre-existing');
  byTarget.push({ target, rounds, passed });
}

for (const l of lines) appendFileSync(out, JSON.stringify(l) + '\n');
console.log(`${lines.length}건을 ${out}에 추가했습니다`);
console.log('항목별 (기본 리뷰어):');
for (const [check, c] of Object.entries(byCheck).sort()) {
  const resolved = c.total - c.unresolved;
  const adoption = resolved ? (c.fixed / resolved).toFixed(2) : '-';
  console.log(`  ${check}: ${c.total}건, 채택률 ${adoption}, 고침 ${c.fixed} / 틀림 ${c.wrong} / 의도 ${c.intentional} / 사소 ${c.minor} / 해로움 ${c.harmful} / 미판정 ${c.unresolved}`);
}
console.log('대상별:');
for (const t of byTarget) {
  const state = t.passed === null ? '리뷰 기록 없음' : `${t.rounds}회차, ${t.passed ? '통과' : '남은 지적 있음'}`;
  console.log(`  ${t.target}: ${state}`);
}
