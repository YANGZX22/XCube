// Exercise the production input scripts in a real Chromium document without an OS keyboard.
// Run: node tools/test-builtin-browser-input.cjs
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const { chromium } = require(process.env.XCUBE_PLAYWRIGHT_PATH ||
  '/Users/mac/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/BuiltinBrowserInput.ets'), 'utf8');
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
}).outputText, context);
const { BROWSER_FOCUSED_EDITOR_SCRIPT, buildBrowserInsertTextScript, parseBrowserInputStatus } = context.exports;
const pageSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/BuiltinBrowserPage.ets'), 'utf8');
vm.runInNewContext(ts.transpileModule(pageSource, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
}).outputText, context);
const { buildBrowserPageTextScript, parseBrowserPageText, buildBrowserFragmentScript } = context.exports;

(async () => {
  const executablePath = process.env.XCUBE_CHROMIUM_PATH ||
    (fs.existsSync(chromium.executablePath()) ? chromium.executablePath() : '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome');
  const browser = await chromium.launch({ headless: true, executablePath });
  let passed = 0;
  try {
    const page = await browser.newPage();
    const test = async (name, fn) => { await fn(); passed++; console.log(`PASS ${name}`); };
    const probe = () => page.evaluate(BROWSER_FOCUSED_EDITOR_SCRIPT);
    const insert = (text, expiresAt = Date.now() + 2000) => page.evaluate(buildBrowserInsertTextScript(text, expiresAt));

    await test('rendered page text paginates without scrolling, exposing input values or hidden content', async () => {
      await page.setContent('<nav>Outside main</nav><main><h1>Guide for authors</h1>' +
        '<p>' + '中文 Article structure and References. '.repeat(100) + '</p>' +
        '<p hidden>PRIVATE HIDDEN</p><div style="display:none"><span>PRIVATE CSS</span></div>' +
        '<input value="PRIVATE INPUT"><textarea>PRIVATE EDITOR</textarea>' +
        '<div contenteditable>PRIVATE DRAFT</div><script>globalThis.secret = "PRIVATE SCRIPT";</script></main>');
      const read = async start => parseBrowserPageText(await page.evaluate(buildBrowserPageTextScript(start, 113, Date.now() + 2000)), start, 113);
      let cursor = 0, text = '', chunks = 0;
      while (true) {
        const result = await read(cursor);
        assert.equal(result.text.length <= 113, true);
        text += result.text;
        chunks++;
        if (!result.has_more) break;
        assert.ok(result.next_start > cursor);
        cursor = result.next_start;
        assert.ok(chunks < 100);
      }
      assert.ok(chunks > 10);
      assert.equal(text.match(/中文/g).length, 100);
      assert.match(text, /Guide for authors/);
      assert.equal(text.includes('PRIVATE'), false);
      assert.equal(text.includes('Outside main'), false);
      assert.equal(await page.evaluate(() => scrollY), 0);
      await assert.rejects(page.evaluate(buildBrowserPageTextScript(0, 100, Date.now() - 1)), /page_read_expired/);
      assert.throws(() => parseBrowserPageText('[]', 0, 100), /无效/);
    });

    await test('same-page fragments scroll to actual anchors without reloading and report missing anchors', async () => {
      let requests = 0;
      await page.route('https://browser-fixture.test/**', route => {
        requests++;
        return route.fulfill({ contentType: 'text/html; charset=utf-8', body: '<main><p>Guide</p><div style="height:2000px"></div>' +
          '<h2 id="article-structure">Article structure</h2><h2 id="章节">References</h2>' +
          '<div style="height:2000px"></div></main>' });
      });
      await page.goto('https://browser-fixture.test/guide');
      await page.evaluate(() => { globalThis.preserved = 'same document'; });
      const jump = url => page.evaluate(buildBrowserFragmentScript(url, Date.now() + 2000));
      assert.equal(await jump('https://browser-fixture.test/guide#article-structure'), 'moved');
      assert.ok(await page.evaluate(() => scrollY > 1500));
      assert.equal(await jump('https://browser-fixture.test/guide#%E7%AB%A0%E8%8A%82'), 'moved');
      assert.equal(await jump('https://browser-fixture.test/guide#nonexistent'), 'missing');
      assert.equal(await jump('https://browser-fixture.test/other#article-structure'), 'different_document');
      assert.equal(await page.evaluate(() => globalThis.preserved), 'same document');
      assert.equal(requests, 1);
      await page.unroute('https://browser-fixture.test/**');
    });

    await test('a LuCI-style standard form submits once after focused insertion, by Enter or its submit button', async () => {
      // Local markup only: never send credentials or form requests to the reported router.
      for (const action of ['enter', 'click', 'button-enter']) {
        await page.setContent('<form method="post"><input name="luci_username" id="luci_username" type="text">' +
          '<input name="luci_password" id="luci_password" type="password">' +
          '<button type="submit">确认</button></form>');
        await page.evaluate(() => {
          globalThis.submissions = [];
          document.querySelector('form').addEventListener('submit', event => {
            event.preventDefault();
            globalThis.submissions.push(Object.fromEntries(new FormData(event.target)));
          });
        });
        await page.locator('#luci_username').focus();
        assert.equal(await insert('fixture-user'), 'inserted');
        await page.locator('#luci_password').focus();
        assert.equal(await insert('fixture-password'), 'inserted');
        if (action === 'click') {
          const rect = await page.locator('button').boundingBox();
          await page.mouse.move(rect.x + rect.width / 2, rect.y + rect.height / 2);
          await page.mouse.down();
          await page.waitForTimeout(50);
          await page.mouse.up();
        } else {
          if (action === 'button-enter') await page.locator('button').focus();
          await page.keyboard.press('Enter');
        }
        assert.deepEqual(await page.evaluate(() => globalThis.submissions), [
          { luci_username: 'fixture-user', luci_password: 'fixture-password' }
        ]);
      }
    });

    await test('Chinese text replaces the selected range, emits input and preserves the caret', async () => {
      await page.setContent('<input id="field" value="abcDEFghi"><output id="out"></output>');
      await page.evaluate(() => {
        const el = document.querySelector('#field');
        el.addEventListener('input', () => document.querySelector('#out').textContent = el.value);
        el.focus(); el.setSelectionRange(3, 6);
      });
      assert.equal(await probe(), 'editable');
      assert.equal(await insert('你好 ✓'), 'inserted');
      assert.equal(await page.locator('#field').inputValue(), 'abc你好 ✓ghi');
      assert.equal(await page.locator('#out').textContent(), 'abc你好 ✓ghi');
      assert.equal(await page.locator('#field').evaluate(el => el.selectionStart), 7);
    });

    await test('multiline and code-like text stay literal and never become JavaScript', async () => {
      await page.setContent('<textarea id="field"></textarea>');
      await page.locator('#field').focus();
      const text = '中文\n"; globalThis.unwanted = true; // \\ ` ${notCode}';
      assert.equal(await insert(text), 'inserted');
      assert.equal(await page.locator('#field').inputValue(), text);
      assert.equal(await page.evaluate(() => globalThis.unwanted), undefined);
    });

    await test('native setter bypasses a framework value tracker and input notifies the controlled state', async () => {
      await page.setContent('<input id="field" value="old"><output id="out"></output>');
      await page.evaluate(() => {
        const el = document.querySelector('#field');
        const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        let tracked = el.value;
        Object.defineProperty(el, 'value', {
          get() { return descriptor.get.call(this); },
          set(value) { tracked = value; descriptor.set.call(this, value); }
        });
        el.addEventListener('input', () => {
          if (tracked !== el.value) document.querySelector('#out').textContent = el.value;
          tracked = el.value;
        });
        el.focus(); el.select();
      });
      assert.equal(await insert('新的值'), 'inserted');
      assert.equal(await page.locator('#out').textContent(), '新的值');
    });

    await test('contenteditable uses Chromium editing and preserves surrounding content', async () => {
      await page.setContent('<div id="field" contenteditable="true"><b>hello</b> world</div>');
      await page.evaluate(() => {
        const el = document.querySelector('#field'); el.focus();
        const range = document.createRange(); range.selectNodeContents(el.firstChild);
        const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
      });
      assert.equal(await probe(), 'editable');
      assert.equal(await insert('你好'), 'inserted');
      assert.equal(await page.locator('#field').textContent(), '你好 world');
    });

    await test('same-origin iframe and open shadow root resolve the actual focused editor', async () => {
      await page.setContent('<iframe id="frame" srcdoc="<input id=field>"></iframe><div id="shadow"></div>');
      const frameField = page.frameLocator('#frame').locator('#field');
      await frameField.focus();
      assert.equal(await probe(), 'editable');
      assert.equal(await insert('iframe 中文'), 'inserted');
      assert.equal(await frameField.inputValue(), 'iframe 中文');
      await page.evaluate(() => {
        const shadow = document.querySelector('#shadow').attachShadow({ mode: 'open' });
        shadow.innerHTML = '<textarea></textarea>'; shadow.querySelector('textarea').focus();
      });
      assert.equal(await probe(), 'editable');
      assert.equal(await insert('shadow 中文'), 'inserted');
      assert.equal(await page.evaluate(() => document.querySelector('#shadow').shadowRoot.querySelector('textarea').value), 'shadow 中文');
    });

    await test('opaque iframe is reported explicitly without inspecting or changing its field', async () => {
      await page.setContent('<iframe id="frame" sandbox="allow-scripts" srcdoc="<input id=field>"></iframe>');
      const field = page.frameLocator('#frame').locator('#field');
      await field.focus();
      assert.equal(await probe(), 'opaque');
      assert.equal(await insert('must not insert'), 'opaque');
      assert.equal(await field.inputValue(), '');
    });

    await test('readonly, disabled and unfocused controls do not receive text', async () => {
      await page.setContent('<input id="field" readonly value="keep"><button id="button">button</button>');
      await page.locator('#field').focus();
      assert.equal(await probe(), 'none');
      assert.equal(await insert('no'), 'none');
      await page.locator('#button').focus();
      assert.equal(await probe(), 'none');
      await page.locator('#field').evaluate(el => { el.readOnly = false; el.disabled = true; el.focus(); });
      assert.equal(await probe(), 'none');
      assert.equal(await page.locator('#field').inputValue(), 'keep');
    });

    await test('beforeinput cancellation and focus changes cannot redirect or duplicate insertion', async () => {
      await page.setContent('<input id="field" value="keep"><input id="other">');
      await page.locator('#field').evaluate(el => {
        el.focus(); el.addEventListener('beforeinput', event => event.preventDefault(), { once: true });
      });
      assert.equal(await insert('no'), 'rejected');
      await page.locator('#field').evaluate(el => {
        el.addEventListener('beforeinput', () => document.querySelector('#other').focus(), { once: true });
      });
      assert.equal(await insert('no'), 'changed');
      assert.equal(await page.locator('#field').inputValue(), 'keep');
      assert.equal(await page.locator('#other').inputValue(), '');
    });

    await test('expired or overlong input is rejected without changing the value', async () => {
      await page.setContent('<input id="field" maxlength="4" value="old">');
      await page.locator('#field').evaluate(el => { el.focus(); el.setSelectionRange(3, 3); });
      assert.equal(await insert('too long'), 'too_long');
      assert.equal(await insert('x', Date.now() - 1000), 'expired');
      assert.equal(await page.locator('#field').inputValue(), 'old');
    });

    await test('a focused field remains writable when another tab is brought to the front', async () => {
      await page.setContent('<input id="field">'); await page.locator('#field').focus();
      const foreground = await browser.newPage(); await foreground.bringToFront();
      assert.equal(await probe(), 'editable');
      assert.equal(await insert('后台输入'), 'inserted');
      assert.equal(await page.locator('#field').inputValue(), '后台输入');
      await foreground.close();
    });

    await test('the host accepts only recognized status values, never page contents', async () => {
      assert.equal(parseBrowserInputStatus('"editable"'), 'editable');
      assert.equal(parseBrowserInputStatus('inserted'), 'inserted');
      assert.throws(() => parseBrowserInputStatus('{"value":"private"}'), /状态无效/);
    });
    console.log(`${passed} real-browser input tests passed.`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
