// 브라우저 E2E (Playwright). 사용: NODE_PATH=$(npm root -g) node scripts/e2e.js <url> <mode> <outDir>
//   mode: preview | shared   (shared = 로컬 서버 또는 Supabase 모의 서버, 조회 PIN 0000 / 편집 PIN 1234)
// 보통은 scripts/e2e.sh 로 실행한다.
const { chromium } = require('playwright');
const [,, URL = 'http://127.0.0.1:8767/', MODE = 'preview', OUT = '/tmp'] = process.argv;
(async () => {
  const shared = MODE === 'shared'; const r = {}; const errors = [];
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' }).catch(() => chromium.launch());
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } }); const P = await ctx.newPage();
  P.on('pageerror', e => errors.push(e.message));
  P.on('console', m => { if (m.type() === 'error' && !/net::ERR|404|40[03]|favicon/.test(m.text())) errors.push('console: ' + m.text()); });
  await P.goto(URL, { waitUntil: 'networkidle' }); await P.waitForTimeout(400);
  if (shared) { r.lock = await P.locator('#lock.open').count(); await P.fill('#viewPinInput', '0000'); await P.click('#lock button[type=submit]'); await P.waitForTimeout(800); }
  r.title = await P.locator('#boardName').innerText();
  r.logos = await P.locator('.logos img').evaluateAll(els => els.every(e => e.naturalWidth > 0));
  r.tabs = (await P.locator('.segment button').allInnerTexts()).map(t => t.replace(/\s+/g, ' ').trim());
  if (shared) P.once('dialog', d => d.accept('1234'));
  await P.keyboard.press('n'); await P.waitForTimeout(300);
  await P.fill('#scheduleForm [name=title]', 'E2E 일정'); await P.click('#catPicker button.cat-회의');
  await P.click('#scheduleForm button[type=submit]'); await P.waitForTimeout(700);
  r.schedSaved = await P.locator('.event-title', { hasText: 'E2E 일정' }).count();
  await P.locator('.event-time').first().click(); await P.waitForTimeout(250); r.popOpen = await P.locator('#pop.open').count();
  await P.fill('#pop [name=start]', '15:00'); await P.click('#pop button[type=submit]'); await P.waitForTimeout(600); r.timeChanged = await P.locator('.event-time', { hasText: '15:00' }).count();
  await P.click('.segment [data-tab=schedule]'); await P.waitForTimeout(300);
  r.calendar = await P.locator('.cal-grid').count(); r.calEvent = await P.locator('.cal-ev', { hasText: 'E2E 일정' }).count();
  await P.screenshot({ path: `${OUT}/e2e-${MODE}-calendar.png` });
  await P.click('.segment [data-tab=schedule]'); await P.waitForTimeout(300); r.backToList = await P.locator('.cal-grid').count() === 0;
  P.once('dialog', d => d.accept('E2E 보드')); await P.click('.board-add'); await P.waitForTimeout(800);
  r.boardTitle = await P.locator('#boardName').innerText(); r.boardEmpty = await P.locator('.event').count();
  await P.click('#boardBtn'); await P.waitForTimeout(200); await P.locator('#boardMenu button', { hasText: '지휘역량강화센터' }).click(); await P.waitForTimeout(700);
  r.mainBack = await P.locator('.event-title', { hasText: 'E2E 일정' }).count();
  await P.click('.segment [data-tab=tasks]'); await P.waitForTimeout(300);
  await P.keyboard.press('n'); await P.waitForTimeout(300); await P.fill('#taskForm [name=title]', 'E2E 업무'); await P.click('#taskCatPicker button.tcat-예산'); await P.fill('#taskForm [name=owner]', '홍길동');
  await P.click('#taskForm button[type=submit]'); await P.waitForTimeout(700);
  r.taskSaved = await P.locator('#taskList .task.tcat-예산 .task-title', { hasText: 'E2E 업무' }).count();
  r.ownerChip = await P.locator('#tasksOwnerFilters .chip', { hasText: '홍길동' }).count();
  await P.screenshot({ path: `${OUT}/e2e-${MODE}-tasks.png` });
  await P.click('.segment [data-tab=personal]'); await P.waitForTimeout(300);
  await P.fill('#loginForm [name=uid]', '032-870-1234'); await P.fill('#loginForm [name=uname]', '홍길동'); await P.click('#loginSubmit'); await P.waitForTimeout(800);
  r.personalName = await P.locator('#personalSummary .name').innerText().catch(() => '');
  await P.keyboard.press('n'); await P.waitForTimeout(300); await P.fill('#taskForm [name=title]', 'E2E 개인'); await P.click('#taskForm button[type=submit]'); await P.waitForTimeout(700);
  r.personalSaved = await P.locator('#personalList .task-title', { hasText: 'E2E 개인' }).count();
  await P.click('.segment [data-tab=tasks]'); await P.waitForTimeout(200); r.teamNoPersonal = await P.locator('#taskList .task-title', { hasText: 'E2E 개인' }).count();
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true }); const Q = await ctx2.newPage(); Q.on('pageerror', e => errors.push('mobile: ' + e.message));
  await Q.goto(URL + '#personal', { waitUntil: 'networkidle' }); await Q.waitForTimeout(400);
  if (shared) { await Q.fill('#viewPinInput', '0000'); await Q.click('#lock button[type=submit]'); await Q.waitForTimeout(800); }
  await Q.fill('#loginForm [name=uid]', '1234'); await Q.fill('#loginForm [name=uname]', '김영희'); await Q.click('#loginSubmit'); await Q.waitForTimeout(700);
  r.wrongName = await Q.locator('#loginErr').innerText();
  await Q.fill('#loginForm [name=uname]', '홍길동'); await Q.click('#loginSubmit'); await Q.waitForTimeout(800);
  r.otherDeviceSees = shared ? await Q.locator('#personalList .task-title', { hasText: 'E2E 개인' }).count() : 'n/a';
  r.mobileHscroll = await Q.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
  await Q.screenshot({ path: `${OUT}/e2e-${MODE}-mobile.png`, fullPage: true });
  const expect = { logos: true, schedSaved: 1, popOpen: 1, timeChanged: 1, calendar: 1, calEvent: 1, backToList: true, boardTitle: 'E2E 보드', boardEmpty: 0, mainBack: 1, taskSaved: 1, ownerChip: 1, personalName: '홍길동', personalSaved: 1, teamNoPersonal: 0, mobileHscroll: false };
  if (shared) Object.assign(expect, { lock: 1, otherDeviceSees: 1 });
  const fails = Object.entries(expect).filter(([k, v]) => JSON.stringify(r[k]) !== JSON.stringify(v)).map(([k, v]) => `${k}: got ${JSON.stringify(r[k])}, want ${JSON.stringify(v)}`);
  console.log(JSON.stringify({ mode: MODE, result: r, fails, errors }, null, 1));
  await browser.close(); process.exit(fails.length || errors.length ? 1 : 0);
})();
