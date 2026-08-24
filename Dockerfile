FROM mcr.microsoft.com/playwright:v1.62.1-jammy

WORKDIR /app

RUN npm init -y && npm install playwright@1.62.1

RUN cat <<'EOF' > index.js
const { chromium } = require('playwright');

function log(msg) {
  const time = new Date().toISOString().substring(11, 19);
  console.log(`[${time}] ${msg}`);
}

(async () => {
  const sessionCookie = "tR5AEALhfCJnR1ddaZhqQ2nJYRGNAq5yM5OCes2a24w82Fd5P4Grxs9xbEboN06Nrje5GOwObVkOGuzvMUVBgnlyFXXAnlJQQlLy";
  const serverCookie = "48yt9NqKp60s1DRO";

  log("Starting direct test script...");

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage'
    ]
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    viewport: { width: 1920, height: 1080 }
  });

  await context.addCookies([
    { name: 'ATERNOS_SESSION', value: sessionCookie, domain: '.aternos.org', path: '/', httpOnly: true, secure: true, sameSite: 'Lax' },
    { name: 'ATERNOS_SERVER', value: serverCookie, domain: '.aternos.org', path: '/', httpOnly: true, secure: true, sameSite: 'Lax' }
  ]);

  const page = await context.newPage();

  try {
    log("Navigating directly to server dashboard...");
    await page.goto('https://aternos.org/server/', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(5000);

    if (page.url().includes('/go')) {
      log("ERROR: Session cookie invalid or expired!");
      process.exit(1);
    }

    const statusLabel = page.locator('.status-label-body, .server-status-label, .status').first();
    let currentStatus = await statusLabel.innerText({ timeout: 5000 }).catch(() => "unknown");
    log(`Initial Status: "${currentStatus.trim()}"`);

    log("Attempting to trigger Restart / Start button...");
    const restartBtn = page.locator('#restart');
    const startBtn = page.locator('#start');

    if (await restartBtn.isVisible().catch(() => false)) {
      log("Found #restart button. Clicking...");
      await restartBtn.click({ force: true });
    } else if (await startBtn.isVisible().catch(() => false)) {
      log("Found #start button. Clicking...");
      await startBtn.click({ force: true });
    } else {
      log("Neither button visible natively. Executing click via DOM...");
      await page.evaluate(() => {
        const btn = document.querySelector('#restart') || document.querySelector('#start');
        if (btn) btn.click();
      });
    }

    await page.waitForTimeout(3000);

    log("Checking for popups (Confirm / Yes)...");
    const confirmBtn = page.locator('button:has-text("Yes"), #confirm, .btn-confirm').first();
    if (await confirmBtn.isVisible().catch(() => false)) {
      log("Confirmation popup detected! Clicking...");
      await confirmBtn.click({ force: true });
    }

    log("Monitoring status for changes (10 checks)...");
    for (let i = 1; i <= 10; i++) {
      await page.waitForTimeout(4000);
      currentStatus = await statusLabel.innerText({ timeout: 5000 }).catch(() => "unknown");
      log(`[Check ${i}/10] Status: "${currentStatus.trim()}"`);

      if (/saving|stopping|restarting|preparing|loading|starting|queue/i.test(currentStatus)) {
        log("🎉 SUCCESS: Server accepted the command!");
        break;
      }
    }

  } catch (err) {
    log(`CRITICAL ERROR: ${err.message}`);
  } finally {
    log("Closing browser and exiting test run.");
    await browser.close();
    process.exit(0);
  }
})();
EOF

CMD ["node", "index.js"]
