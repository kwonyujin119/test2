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
  P.on('dialog', d => { const m = d.message(); if (m.includes('관리자 PIN')) d.accept('1234'); else if (m.includes('대시보드 이름')) d.accept('E2E 보드'); else if (m.includes('41망에 표시할 이름')) d.accept('테스터'); else if (m.includes('입장코드 4자리')) d.accept(m.includes('교육지원과') ? '0000' : '5948'); else d.accept(); });
  r.noPinPromptOnSave = true;
  await P.keyboard.press('n'); await P.waitForTimeout(300);
  await P.fill('#scheduleForm [name=title]', 'E2E 일정'); await P.click('#catPicker button.cat-회의');
  await P.click('#scheduleForm button[type=submit]'); await P.waitForTimeout(700);
  r.schedSaved = await P.locator('.event-title', { hasText: 'E2E 일정' }).count();
  await P.locator('.event', { hasText: 'E2E 일정' }).locator('.event-time').click(); await P.waitForTimeout(250); r.popOpen = await P.locator('#pop.open').count();
  await P.fill('#pop [name=start]', '15:00'); await P.click('#pop button[type=submit]'); await P.waitForTimeout(600); r.timeChanged = await P.locator('.event-time', { hasText: '15:00' }).count();
  // 다일 일정: 시작만 입력하면 종료가 자동으로 같아지는지, 종료를 +2일로 하면 3일에 걸쳐 표시되는지
  await P.keyboard.press('n'); await P.waitForTimeout(300);
  await P.fill('#scheduleForm [name=title]', 'E2E 출장'); await P.click('#catPicker button.cat-출장');
  await P.fill('#scheduleForm [name=date]', '2026-12-07'); await P.locator('#scheduleForm [name=date]').dispatchEvent('change');
  r.endAuto = await P.locator('#scheduleForm [name=endDate]').inputValue();
  await P.fill('#scheduleForm [name=endDate]', '2026-12-09'); await P.click('#scheduleForm button[type=submit]'); await P.waitForTimeout(700);
  r.multiDays = await P.locator('.event', { hasText: 'E2E 출장' }).count(); r.dayIdx = await P.locator('.event', { hasText: 'E2E 출장' }).locator('.dayidx').allInnerTexts();
  // 구분 '주요업무' → 주요업무 탭 카드 연동
  await P.keyboard.press('n'); await P.waitForTimeout(300);
  await P.fill('#scheduleForm [name=title]', 'E2E 연동 업무'); await P.click('#catPicker button.cat-주요업무'); await P.fill('#scheduleForm [name=date]', '2026-12-15'); await P.locator('#scheduleForm [name=date]').dispatchEvent('change');
  await P.click('#scheduleForm button[type=submit]'); await P.waitForTimeout(1000);
  r.linkedTab = await P.evaluate(() => currentTab()); r.linkedCard = await P.locator('#taskList .task', { hasText: 'E2E 연동 업무' }).count();
  r.linkedDue = (await P.locator('#taskList .task', { hasText: 'E2E 연동 업무' }).locator('.task-foot').innerText()).includes('2026-12-15');
  r.linkedMark = await P.locator('#taskList .task', { hasText: 'E2E 연동 업무' }).locator('.linked').count();
  await P.click('.segment [data-tab=schedule]'); await P.waitForTimeout(300);
  await P.locator('.event', { hasText: 'E2E 연동 업무' }).locator('.event-main').click(); await P.waitForTimeout(300); await P.click('#scheduleDelete'); await P.waitForTimeout(900);
  await P.click('.segment [data-tab=tasks]'); await P.waitForTimeout(300); r.linkedGone = await P.locator('#taskList .task', { hasText: 'E2E 연동 업무' }).count();
  await P.click('.segment [data-tab=schedule]'); await P.waitForTimeout(300);
  await P.click('.segment [data-tab=schedule]'); await P.waitForTimeout(300);
  r.calendar = await P.locator('.cal-grid').count(); r.calEvent = await P.locator('.cal-ev', { hasText: 'E2E 일정' }).count();
  await P.screenshot({ path: `${OUT}/e2e-${MODE}-calendar.png` });
  await P.click('.segment [data-tab=schedule]'); await P.waitForTimeout(300); r.backToList = await P.locator('.cal-grid').count() === 0;
  if (shared) { await P.evaluate(() => changePin()); await P.waitForTimeout(700); }   // 대시보드 + 는 관리자에게만 보인다
  await P.click('.board-add'); await P.waitForTimeout(800);
  r.boardTitle = await P.locator('#boardName').innerText(); r.boardEmpty = await P.locator('.event').count();
  await P.click('#boardBtn'); await P.waitForTimeout(200); await P.locator('#boardMenu button', { hasText: '지휘역량강화센터' }).click(); await P.waitForTimeout(700);
  r.mainBack = await P.locator('.event-title', { hasText: 'E2E 일정' }).count();
  await P.click('.segment [data-tab=tasks]'); await P.waitForTimeout(300);
  await P.keyboard.press('n'); await P.waitForTimeout(300); await P.fill('#taskForm [name=title]', 'E2E 업무'); await P.click('#taskCatPicker button.tcat-예산'); await P.fill('#taskForm [name=owner]', '홍길동');
  await P.click('#taskForm button[type=submit]'); await P.waitForTimeout(700);
  r.taskSaved = await P.locator('#taskList .task.tcat-예산 .task-title', { hasText: 'E2E 업무' }).count();
  await P.locator('#taskList .task', { hasText: 'E2E 업무' }).locator('.done-btn').click(); await P.waitForTimeout(600);
  r.doneOneClick = await P.locator('#taskList .task.done', { hasText: 'E2E 업무' }).count();
  await P.locator('#taskList .task', { hasText: 'E2E 업무' }).locator('.status').click(); await P.waitForTimeout(300);
  r.badgeOpensForm = await P.locator('#taskModal.open').count(); await P.keyboard.press('Escape'); await P.waitForTimeout(200);
  r.ownerChip = await P.locator('#tasksOwnerFilters .chip', { hasText: '홍길동' }).count();
  await P.screenshot({ path: `${OUT}/e2e-${MODE}-tasks.png` });
  // 41망 팀 대화: 이름 정하고 글 보내기 → 내 말풍선, 삭제 버튼, 닫은 뒤 배지 없음
  await P.click('#chatBtn'); await P.waitForTimeout(700); r.chatOpen = await P.locator('#chatModal.open').count();
  r.chatRooms = await P.locator('#chatList .room-row').count(); r.chatRoomIcons = await P.locator('#chatList .room-row .room-ico').count();
  await P.locator('#chatList .room-row', { hasText: '교육지원과' }).locator('.room-main').click(); await P.waitForTimeout(600);   // 틀린 코드(0000) → 거부
  r.chatWrongCode = await P.locator('#chatModal.open .room-row').count() > 0;
  await P.locator('#chatList .room-row', { hasText: '지휘역량강화센터' }).locator('.room-ico').click(); await P.waitForTimeout(800);   // 5948 → 입장
  r.chatRoomTitle = await P.locator('#chatTitle').innerText();
  await P.fill('#chatText', 'E2E 41망 첫 글'); await P.click('#chatSend'); await P.waitForTimeout(900);
  r.chatMine = await P.locator('#chatList .chat-msg.mine .chat-bubble', { hasText: 'E2E 41망 첫 글' }).count();
  r.chatWho = await P.locator('#chatWho b').innerText().catch(() => '');
  await P.screenshot({ path: `${OUT}/e2e-${MODE}-chat.png` });
  await P.click('#chatModal .chat-back'); await P.waitForTimeout(300); r.chatRoomLast = await P.locator('#chatList .room-row', { hasText: '지휘역량강화센터' }).locator('.room-last').innerText();
  await P.click('#chatModal .chat-close'); await P.waitForTimeout(400); r.chatBadgeHidden = await P.locator('#chatBadge').isHidden();
  // 페이지 나누기: 주요업무 5개씩 → 카드 5개 + 쪽 표시, 다음 쪽으로 이동, 기본값(10)으로 복귀
  await P.evaluate(() => setPageSize('tasks', 5)); await P.waitForTimeout(200);
  r.pageCards = await P.locator('#taskList .task').count(); r.pageLabel = await P.locator('#taskList .pager-nav span').innerText().catch(() => '');
  await P.evaluate(() => gotoPage('tasks', 2)); await P.waitForTimeout(300); r.page2Label = await P.locator('#taskList .pager-nav span').innerText().catch(() => '');
  await P.evaluate(() => setPageSize('tasks', 10)); await P.waitForTimeout(200);
  await P.click('.segment [data-tab=personal]'); await P.waitForTimeout(300);
  await P.click('#loginTabRegister'); await P.fill('#loginForm [name=uid]', '032-870-1234'); await P.fill('#loginForm [name=upw]', '1111'); await P.fill('#loginForm [name=uname]', '홍길동'); await P.fill('#loginForm [name=upw2]', '1111'); await P.click('#loginSubmit'); await P.waitForTimeout(800);
  r.personalName = await P.locator('#personalSummary .name').innerText().catch(() => '');
  await P.keyboard.press('n'); await P.waitForTimeout(300); await P.fill('#taskForm [name=title]', 'E2E 개인'); await P.click('#taskForm button[type=submit]'); await P.waitForTimeout(700);
  r.personalSaved = await P.locator('#personalList .task-title', { hasText: 'E2E 개인' }).count();
  // 엑셀 가져오기: 머리글이 2행에 있는 샘플(연번·업무명·구분·기한·상태·담당·비고) → 4건 추가, 재가져오기는 전부 '이미 있음'
  await P.evaluate(() => importExcel()); await P.waitForTimeout(300);
  await P.setInputFiles('#xlFile', require('path').join(__dirname, 'fixtures', 'personal-sample.xlsx')); await P.waitForTimeout(1500);
  r.xlRows = await P.locator('#xlRows tbody tr').count();
  r.xlMap = await P.evaluate(() => [XL.rows[XL.hdr][XL.map.title], XL.rows[XL.hdr][XL.map.due], XL.rows[XL.hdr][XL.map.status], XL.rows[XL.hdr][XL.map.category], XL.rows[XL.hdr][XL.map.detail]].join(','));
  r.xlDue = await P.locator('#xlRows tbody tr').nth(0).locator('td').nth(2).innerText();
  r.xlAddLabel = await P.locator('#xlAddBtn').innerText();
  await P.click('#xlAddBtn'); await P.waitForTimeout(1500);
  r.xlAdded = await P.locator('#personalList .task-title', { hasText: '장비 점검표 갱신' }).count();
  r.xlDone = await P.locator('#personalList .task.done .task-title', { hasText: '결과보고' }).count();
  await P.evaluate(() => importExcel()); await P.waitForTimeout(300);
  await P.setInputFiles('#xlFile', require('path').join(__dirname, 'fixtures', 'personal-sample.xlsx')); await P.waitForTimeout(1200);
  r.xlDupCount = await P.locator('#xlRows .xl-flag', { hasText: '이미 있음' }).count();
  r.xlDupBtnDisabled = await P.locator('#xlAddBtn').isDisabled();
  await P.screenshot({ path: `${OUT}/e2e-${MODE}-excel.png` });
  await P.click('#xlsxModal .sheet-foot .btn.ghost'); await P.waitForTimeout(400);
  await P.click('#menuBtn'); await P.waitForTimeout(200); await P.click('#menuUsers'); await P.waitForTimeout(600);
  r.usersSheet = await P.locator('#usersModal.open').count(); r.usersHasMe = await P.locator('#usersList .user-row', { hasText: '홍길동' }).count();
  await P.click('#usersModal .sheet-foot .btn'); await P.waitForTimeout(300);
  await P.click('.segment [data-tab=tasks]'); await P.waitForTimeout(200); r.teamNoPersonal = await P.locator('#taskList .task-title', { hasText: 'E2E 개인' }).count();
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true }); const Q = await ctx2.newPage(); Q.on('pageerror', e => errors.push('mobile: ' + e.message));
  Q.on('dialog', d => { const m = d.message(); if (m.includes('입장코드 4자리')) d.accept('5948'); else if (m.includes('41망에 표시할 이름')) d.accept('폰사용자'); else d.accept(); });
  await Q.goto(URL + '#personal', { waitUntil: 'networkidle' }); await Q.waitForTimeout(400);
  if (shared) { await Q.fill('#viewPinInput', '0000'); await Q.click('#lock button[type=submit]'); await Q.waitForTimeout(800); }
  await Q.fill('#loginForm [name=uid]', '1234');
  if (shared) { // 미리보기 모드는 브라우저별 저장이라 사용자가 없으므로 공유 모드에서만 검사
    await Q.fill('#loginForm [name=upw]', '9999'); await Q.click('#loginSubmit'); await Q.waitForTimeout(900);
    r.wrongName = await Q.locator('#loginErr').innerText();
    // 예전 방식(이름=비밀번호) 사용자 전환: 서버에 이름 그대로 pin 인 사용자를 만들어 두고 '처음 등록'으로 비밀번호 설정
    await Q.evaluate(() => api.userRegister('5678', '남궁민수', '남궁민수'));
    await Q.click('#loginTabRegister'); await Q.fill('#loginForm [name=uid]', '5678'); await Q.fill('#loginForm [name=upw]', '2222'); await Q.fill('#loginForm [name=uname]', '남궁민수'); await Q.fill('#loginForm [name=upw2]', '2222'); await Q.click('#loginSubmit'); await Q.waitForTimeout(900);
    r.migrated = await Q.locator('#personalSummary .name').innerText().catch(() => '');
    await Q.evaluate(() => logout(true)); await Q.waitForTimeout(300);
    await Q.fill('#loginForm [name=uid]', '5678'); await Q.fill('#loginForm [name=upw]', '2222'); await Q.click('#loginSubmit'); await Q.waitForTimeout(900);
    r.migratedLogin = await Q.locator('#personalSummary .name').innerText().catch(() => '');
    await Q.evaluate(() => logout(true)); await Q.waitForTimeout(300);
    await Q.fill('#loginForm [name=uid]', '1234');
  }
  await Q.fill('#loginForm [name=upw]', '1111'); await Q.click('#loginSubmit'); await Q.waitForTimeout(800);
  r.otherDeviceSees = shared ? await Q.locator('#personalList .task-title', { hasText: 'E2E 개인' }).count() : 'n/a';
  if (shared) {
    r.chatBadgeOther = await Q.locator('#chatBadge').isHidden();   // 입장 전에는 배지 없음
    await Q.click('#chatBtn'); await Q.waitForTimeout(700);
    await Q.locator('#chatList .room-row', { hasText: '지휘역량강화센터' }).locator('.room-ico').click(); await Q.waitForTimeout(900);
    r.chatOtherSees = await Q.locator('#chatList .chat-msg:not(.mine) .chat-bubble', { hasText: 'E2E 41망 첫 글' }).count();
    r.chatOtherName = await Q.locator('#chatList .chat-name', { hasText: '테스터' }).count();
    await Q.screenshot({ path: `${OUT}/e2e-${MODE}-chat-mobile.png` });
    await Q.click('#chatModal .chat-close'); await Q.waitForTimeout(300);
  }
  r.mobileHscroll = await Q.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
  await Q.screenshot({ path: `${OUT}/e2e-${MODE}-mobile.png`, fullPage: true });
  const expect = { logos: true, schedSaved: 1, popOpen: 1, timeChanged: 1, calendar: 1, calEvent: 1, backToList: true, boardTitle: 'E2E 보드', boardEmpty: 0, mainBack: 1, taskSaved: 1, ownerChip: 1, personalName: '홍길동', personalSaved: 1, chatOpen: 1, chatRooms: 4, chatRoomIcons: 4, chatWrongCode: true, chatRoomTitle: '지휘역량강화센터', chatMine: 1, chatWho: '테스터', chatRoomLast: '테스터: E2E 41망 첫 글', chatBadgeHidden: true, pageCards: 5, pageLabel: '1–5 / 8건', page2Label: '6–8 / 8건', xlRows: 4, xlMap: '업무명,기한,상태,구분,비고', xlDue: '2026-10-28', xlAddLabel: '4건 추가', xlAdded: 1, xlDone: 1, xlDupCount: 4, xlDupBtnDisabled: true, teamNoPersonal: 0, mobileHscroll: false, usersSheet: 1, usersHasMe: 1, endAuto: '2026-12-07', multiDays: 3, dayIdx: ['1/3일차', '2/3일차', '3/3일차'], doneOneClick: 1, badgeOpensForm: 1, linkedTab: 'tasks', linkedCard: 1, linkedDue: true, linkedMark: 1, linkedGone: 0 };
  if (shared) Object.assign(expect, { chatBadgeOther: true, chatOtherSees: 1, chatOtherName: 1, pageCards: 1, pageLabel: '', page2Label: '', lock: 1, otherDeviceSees: 1, wrongName: '비밀번호가 맞지 않아요', migrated: '남궁민수', migratedLogin: '남궁민수' });
  const fails = Object.entries(expect).filter(([k, v]) => JSON.stringify(r[k]) !== JSON.stringify(v)).map(([k, v]) => `${k}: got ${JSON.stringify(r[k])}, want ${JSON.stringify(v)}`);
  console.log(JSON.stringify({ mode: MODE, result: r, fails, errors }, null, 1));
  await browser.close(); process.exit(fails.length || errors.length ? 1 : 0);
})();
