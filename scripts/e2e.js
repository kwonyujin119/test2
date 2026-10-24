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
  process.on('unhandledRejection', async e => { try { await P.screenshot({ path: `${OUT}/e2e-${MODE}-FAIL.png` }); } catch (_) {} console.error(String(e && e.message || e).split('\n')[0]); process.exit(1); });   // 실패 지점 화면을 남긴다
  P.on('console', m => { if (m.type() === 'error' && !/net::ERR|404|40[03]|favicon/.test(m.text())) errors.push('console: ' + m.text()); });
  await P.goto(URL, { waitUntil: 'networkidle' }); await P.waitForTimeout(400);
  if (shared) { r.lock = await P.locator('#lock.open').count(); await P.fill('#viewPinInput', '0000'); await P.click('#lock button[type=submit]'); await P.waitForTimeout(800); }
  r.title = await P.locator('#boardName').innerText();
  r.logos = await P.locator('.logos img').evaluateAll(els => els.every(e => e.naturalWidth > 0));
  r.tabs = (await P.locator('.segment button').allInnerTexts()).map(t => t.replace(/\s+/g, ' ').trim());
  P.on('dialog', d => { const m = d.message(); if (m.includes('관리자 PIN')) d.accept('1234'); else if (m.includes('대시보드 이름')) d.accept('E2E 보드'); else if (m.includes('41망에 표시할 이름')) d.accept('테스터'); else if (m.includes('입장코드 4자리')) d.accept(m.includes('교육지원과') ? '0000' : '5948'); else if (m.includes('개인업무에 표시할 이름')) d.accept('홍길동'); else d.accept(); });
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
  // 첨부: + 토글 → 사진·파일 선택 → 대기 칩 2개 → 보내기 → 이미지·파일 카드
  await P.click('#chatPlus'); await P.waitForTimeout(400); r.chatAttachOpen = await P.locator('#attachModal.open').count();
  await P.setInputFiles('#chatFileImg', require('path').join(__dirname, 'fixtures', 'pixel.png')); await P.waitForTimeout(600);
  await P.setInputFiles('#chatFileAny', require('path').join(__dirname, 'fixtures', 'note.txt')); await P.waitForTimeout(400);
  r.chatPending = await P.locator('#chatPending .pend').count(); r.chatStrip = await P.locator('#attachStrip .att-item .num').allInnerTexts();
  await P.click('#attachSendBtn'); await P.waitForTimeout(2200);
  r.chatImg = await P.locator('#chatList .chat-msg.mine .chat-img img').count();
  r.chatImgLoaded = await P.locator('#chatList .chat-msg.mine .chat-img img').first().evaluate(i => i.complete && i.naturalWidth > 0).catch(() => false);
  r.chatFileCard = await P.locator('#chatList .chat-msg.mine .chat-file .fn', { hasText: 'note.txt' }).count();
  r.chatPendingCleared = await P.locator('#chatPending .pend').count();
  r.chatThumb = await P.locator('#chatList .chat-msg.mine .chat-img img').first().getAttribute('src').then(v => /thumb|data:|\/files\//.test(v || '') || (v || '').includes('/chat/'));
  // 우클릭 메뉴: 사진에서 → 답장·이미지 복사·글 복사·공유·사진 저장·삭제. 답장 → 인용 말풍선. 삭제 → (삭제된 메시지)
  await P.locator('#chatList .chat-msg.mine .chat-img').first().click({ button: 'right' }); await P.waitForTimeout(250);
  r.ctxItems = await P.locator('#ctxMenu.open button').allInnerTexts().then(a => a.map(t => t.replace(/\s+/g, ' ').trim()));
  await P.locator('#ctxMenu button', { hasText: '답장' }).click(); await P.waitForTimeout(200); r.replyBar = await P.locator('#chatReplyBar').isVisible();
  await P.fill('#chatText', 'E2E 답장'); await P.click('#chatSend'); await P.waitForTimeout(900);
  r.replyQuote = await P.locator('#chatList .chat-msg.mine .chat-quote').count();
  await P.locator('#chatList .chat-msg.mine .chat-bubble', { hasText: 'E2E 답장' }).click({ button: 'right' }); await P.waitForTimeout(250);
  await P.locator('#ctxMenu button', { hasText: '삭제' }).click(); await P.waitForTimeout(900);
  r.deletedPh = await P.locator('#chatList .chat-bubble.deleted', { hasText: '(삭제된 메시지)' }).count();
  // Ctrl+V: 클립보드의 캡처 이미지를 첨부로
  await P.evaluate(async () => { const b = await (await fetch('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')).blob(); const dt = new DataTransfer(); dt.items.add(new File([b], 'image.png', { type: 'image/png' })); document.getElementById('chatText').dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true })); });
  await P.waitForTimeout(700); r.pasteAttached = await P.locator('#chatPending .pend .pend-name').first().innerText().then(t => t.startsWith('캡처-'));
  await P.evaluate(() => { CHAT.pending = []; renderPending(); });
  await P.screenshot({ path: `${OUT}/e2e-${MODE}-chat.png` });
  await P.click('#chatModal .chat-back'); await P.waitForTimeout(300); r.chatRoomLast = await P.locator('#chatList .room-row', { hasText: '지휘역량강화센터' }).locator('.room-last').innerText();
  await P.click('#chatModal .chat-close'); await P.waitForTimeout(400); r.chatBadgeHidden = await P.locator('#chatBadge').isHidden();
  // 넓게 보기: 요약·사이드바 숨김, 카드 3열, 해제 알약. 끄면 원래대로
  await P.evaluate(() => toggleWide(true)); await P.waitForTimeout(300);
  r.wideOn = await P.evaluate(() => document.body.classList.contains('wide') && getComputedStyle(document.getElementById('tasksSummary')).display === 'none' && getComputedStyle(document.getElementById('taskList')).gridTemplateColumns.split(' ').length === 3);
  r.wideBar = await P.locator('#wideBar').isVisible();
  await P.click('#wideExit'); await P.waitForTimeout(300); r.wideOff = await P.evaluate(() => !document.body.classList.contains('wide') && getComputedStyle(document.getElementById('tasksSummary')).display !== 'none');
  // 키워드 검색: 'E2E 업무' = 두 단어 AND → 두 단어 모두 표시(mark 2개) + 다른 카드 숨김, 지우면 복귀. 달력 보기 전환(해당 날짜 hit) 후 목록 복귀
  const tasksBefore = await P.locator('#taskList .task').count();
  await P.evaluate(() => setQ('tasks', 'E2E 업무')); await P.waitForTimeout(500);
  r.qMarks = await P.locator('#taskList .task-title mark').count(); r.qOnly = await P.locator('#taskList .task').count();
  r.qFabHidden = await P.locator('#qfab').isHidden();
  await P.evaluate(() => toggleTaskView('tasks', 'calendar')); await P.waitForTimeout(500);
  r.tcal = await P.locator('#taskList .cal-grid').count(); r.tcalHit = await P.locator('#taskList .cal-undated .cal-ev', { hasText: 'E2E 업무' }).count();
  await P.screenshot({ path: `${OUT}/e2e-${MODE}-taskcal.png` });
  await P.evaluate(() => { setQ('tasks', ''); toggleTaskView('tasks', 'list'); }); await P.waitForTimeout(1200);
  r.tcalBack = await P.locator('#taskList .cal-grid').count(); r.qCleared = (await P.locator('#taskList .task').count()) === tasksBefore;
  // 사진 첨부: 업무 시트에 pixel.png 를 넣고 저장 → 카드에 썸네일. 다시 열면 기존 사진 1장 + × 로 빼기
  await P.locator('#taskList .task', { hasText: 'E2E 업무' }).first().click(); await P.waitForTimeout(400);
  await P.setInputFiles('#attIn_task', require('path').join(__dirname, 'fixtures', 'pixel.png')); await P.waitForTimeout(800);
  r.attPending = await P.locator('#attGrid_task .att-thumb').count();
  await P.click('#taskForm button[type=submit]'); await P.waitForTimeout(1500);
  r.attCard = await P.locator('#taskList .task', { hasText: 'E2E 업무' }).first().locator('.atts a').count();
  r.attLoaded = await P.locator('#taskList .task', { hasText: 'E2E 업무' }).first().locator('.atts img').first().evaluate(im => im.complete && im.naturalWidth > 0);
  await P.locator('#taskList .task', { hasText: 'E2E 업무' }).first().click(); await P.waitForTimeout(400);
  r.attExisting = await P.locator('#attGrid_task .att-thumb a').count();
  await P.keyboard.press('Escape'); await P.waitForTimeout(300);
  // 사용 안내 시트: ⋮ → 사용 안내 로 열리고 Esc 로 닫힘
  await P.evaluate(() => openHelp()); await P.waitForTimeout(300); r.helpOpen = await P.evaluate(() => document.getElementById('helpModal').classList.contains('open'));
  await P.keyboard.press('Escape'); await P.waitForTimeout(300); r.helpClosed = await P.evaluate(() => !document.getElementById('helpModal').classList.contains('open'));
  // 페이지 나누기: 주요업무 5개씩 → 카드 5개 + 쪽 표시, 다음 쪽으로 이동, 기본값(10)으로 복귀
  await P.evaluate(() => setPageSize('tasks', 5)); await P.waitForTimeout(200);
  r.pageCards = await P.locator('#taskList .task').count(); r.pageLabel = await P.locator('#taskList .pager-nav span').innerText().catch(() => '');
  await P.evaluate(() => gotoPage('tasks', 2)); await P.waitForTimeout(300); r.page2Label = await P.locator('#taskList .pager-nav span').innerText().catch(() => '');
  await P.evaluate(() => setPageSize('tasks', 10)); await P.waitForTimeout(200);
  await P.click('.segment [data-tab=personal]'); await P.waitForTimeout(300);
  await P.fill('#loginForm [name=uid]', '032-870-1234'); await P.fill('#loginForm [name=upw]', '1111'); await P.click('#loginSubmit'); await P.waitForTimeout(900);   // 처음 → confirm 수락 → 자동 등록
  r.personalDefaultName = await P.locator('#personalSummary .name').innerText().catch(() => '');
  await P.evaluate(() => changeMyName()); await P.waitForTimeout(600);
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
    await Q.fill('#loginForm [name=uid]', '1234');
  }
  await Q.fill('#loginForm [name=upw]', '1111'); await Q.click('#loginSubmit'); await Q.waitForTimeout(800);
  if (shared) { await Q.click('#menuBtn'); await Q.waitForTimeout(200); r.menuAdminLogin = await Q.locator('#menu button:visible').last().innerText(); await Q.keyboard.press('Escape'); await Q.waitForTimeout(200); }
  r.otherDeviceSees = shared ? await Q.locator('#personalList .task-title', { hasText: 'E2E 개인' }).count() : 'n/a';
  if (shared) {
    r.chatBadgeOther = await Q.locator('#chatBadge').isHidden();   // 입장 전에는 배지 없음
    await Q.click('#chatBtn'); await Q.waitForTimeout(700);
    await Q.locator('#chatList .room-row', { hasText: '지휘역량강화센터' }).locator('.room-ico').click(); await Q.waitForTimeout(900);
    r.chatOtherSees = await Q.locator('#chatList .chat-msg:not(.mine) .chat-bubble', { hasText: 'E2E 41망 첫 글' }).count();
    r.chatOtherName = await Q.locator('#chatList .chat-name', { hasText: '테스터' }).count() > 0;
    r.chatOtherImg = await Q.locator('#chatList .chat-img img').first().evaluate(i => i.complete && i.naturalWidth > 0).catch(() => false);
    await Q.screenshot({ path: `${OUT}/e2e-${MODE}-chat-mobile.png` });
    await Q.click('#chatModal .chat-close'); await Q.waitForTimeout(300);
  }
  r.mobileHscroll = await Q.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
  await Q.screenshot({ path: `${OUT}/e2e-${MODE}-mobile.png`, fullPage: true });
  const expect = { logos: true, schedSaved: 1, popOpen: 1, timeChanged: 1, calendar: 1, calEvent: 1, backToList: true, boardTitle: 'E2E 보드', boardEmpty: 0, mainBack: 1, taskSaved: 1, ownerChip: 1, personalName: '홍길동', personalDefaultName: '직원 1234', personalSaved: 1, wideOn: true, wideBar: true, wideOff: true, helpOpen: true, helpClosed: true, attPending: 1, attCard: 1, attLoaded: true, attExisting: 1, qMarks: 2, qOnly: 1, qFabHidden: true, tcal: 1, tcalHit: 1, tcalBack: 0, qCleared: true, chatOpen: 1, chatRooms: 4, chatRoomIcons: 4, chatWrongCode: true, chatRoomTitle: '지휘역량강화센터', chatMine: 1, chatWho: '테스터', chatAttachOpen: 1, chatPending: 2, chatStrip: ['1', '2'], chatImg: 1, chatImgLoaded: true, chatFileCard: 1, chatPendingCleared: 0, chatThumb: true, ctxItems: ['답장', '이미지 복사', '글 복사 글 없는 메시지', '공유', '사진 저장', '삭제'], replyBar: true, replyQuote: 1, deletedPh: 1, pasteAttached: true, chatRoomLast: '테스터: (삭제된 메시지)', chatBadgeHidden: true, pageCards: 5, pageLabel: '1–5 / 8건', page2Label: '6–8 / 8건', xlRows: 4, xlMap: '업무명,기한,상태,구분,비고', xlDue: '2026-10-28', xlAddLabel: '4건 추가', xlAdded: 1, xlDone: 1, xlDupCount: 4, xlDupBtnDisabled: true, teamNoPersonal: 0, mobileHscroll: false, usersSheet: 1, usersHasMe: 1, endAuto: '2026-12-07', multiDays: 3, dayIdx: ['1/3일차', '2/3일차', '3/3일차'], doneOneClick: 1, badgeOpensForm: 1, linkedTab: 'tasks', linkedCard: 1, linkedDue: true, linkedMark: 1, linkedGone: 0 };
  if (shared) Object.assign(expect, { chatBadgeOther: true, chatOtherSees: 1, chatOtherImg: true, menuAdminLogin: '관리자 로그인', chatOtherName: true, pageCards: 1, pageLabel: '', page2Label: '', lock: 1, otherDeviceSees: 1, wrongName: '비밀번호가 맞지 않아요' });
  const fails = Object.entries(expect).filter(([k, v]) => JSON.stringify(r[k]) !== JSON.stringify(v)).map(([k, v]) => `${k}: got ${JSON.stringify(r[k])}, want ${JSON.stringify(v)}`);
  console.log(JSON.stringify({ mode: MODE, result: r, fails, errors }, null, 1));
  await browser.close(); process.exit(fails.length || errors.length ? 1 : 0);
})();
