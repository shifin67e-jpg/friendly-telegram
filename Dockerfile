FROM mcr.microsoft.com/playwright:v1.62.1-jammy

WORKDIR /app

# 1. Install Playwright and node-cron for scheduling
RUN npm init -y && npm install playwright@1.62.1 node-cron

# 2. Scheduled Auto-Restart Script
RUN cat <<'EOF' > index.js
const { chromium } = require('playwright');
const cron = require('node-cron');

function log(message) {
  const time = new Date().toISOString().substring(11, 19);
  console.log(`[${time}] ${message}`);
}

const randomSleep = (minMs, maxMs) => {
  const delay = Math.floor(Math.random() * (maxMs - minMs + 1)) + minMs;
  return new Promise(resolve => setTimeout(resolve, delay));
};

async function getLiveStatus(page) {
  try {
    const statusEl = await page.waitForSelector('.status-label-body, .server-status-label, .status', { timeout: 8000 });
    if (statusEl) {
      const text = await statusEl.innerText();
      return text.trim().toLowerCase();
    }
  } catch (err) {
    const title = await page.title().catch(() => 'Unknown Title');
    const currentUrl = page.url();
    log(`[DOM Alert] Could not locate status element. Page Title: "${title}" | URL: ${currentUrl}`);
  }
  return 'unknown';
}

async function performRestart() {
  const sessionCookie = "tR5AEALhfCJnR1ddaZhqQ2nJYRGNAq5yM5OCes2a24w82Fd5P4Grxs9xbEboN06Nrje5GOwObVkOGuzvMUVBgnlyFXXAnlJQQlLy";
  const serverCookie = "48yt9NqKp60s1DRO";
  const targetServerName = "Lets_Play_Java.aternos.me";

  log(`--- INITIATING RESTART SEQUENCE FOR ${targetServerName} ---`);
  log('Launching browser session...');
  
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-blink-features=AutomationControlled',
      '--disable-infobars',
      '--ignore-certificate-errors'
    ]
  });
  
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    viewport: { width: 1920, height: 1080 },
    locale: 'en-US',
    timezoneId: 'Asia/Kolkata'
  });

  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    window.chrome = { runtime: {} };
  });

  await context.addCookies([
    { name: 'ATERNOS_SESSION', value: sessionCookie, domain: '.aternos.org', path: '/', httpOnly: true, secure: true, sameSite: 'Lax' },
    { name: 'ATERNOS_SERVER', value: serverCookie, domain: '.aternos.org', path: '/', httpOnly: true, secure: true, sameSite: 'Lax' }
  ]);

  const page = await context.newPage();

  try {
    log('Navigating directly to server dashboard...');
    await page.goto('https://aternos.org/server/', { waitUntil: 'networkidle', timeout: 60000 });
    await randomSleep(3000, 5000);

    if (page.url().includes('/go')) {
      throw new Error('SESSION EXPIRED: Please update your ATERNOS_SESSION cookie.');
    }

    log('Triggering Restart...');
    let restartTriggered = false;

    for (let attempt = 1; attempt <= 10; attempt++) {
      // Click restart/start buttons
      await page.evaluate(() => {
        const restart = document.querySelector('#restart');
        const start = document.querySelector('#start'); 
        if (restart && restart.offsetParent !== null) restart.click();
        else if (start && start.offsetParent !== null) start.click();
      }).catch(() => {});

      await randomSleep(1000, 2000);

      // Dismiss confirmation prompts
      await page.evaluate(() => {
        const buttons = Array.from(document.querySelectorAll('button, a, .btn, #confirm, .btn-danger, .btn-confirm'));
        buttons.forEach(b => {
          const text = (b.innerText || b.textContent || '').trim().toLowerCase();
          if (text === 'yes' || text.includes('confirm') || text.includes('accept')) {
            b.click();
          }
        });
      }).catch(() => {});

      const currentStatus = await getLiveStatus(page);
      log(`[Init Attempt ${attempt}/10] Live Status: "${currentStatus}"`);

      if (/saving|stopping|restarting|preparing|loading|starting|queue|min/i.test(currentStatus)) {
        log(`SUCCESS: Reboot sequence triggered! Server is now "${currentStatus}".`);
        restartTriggered = true;
        break;
      }

      await randomSleep(3000, 5000);
    }

    if (!restartTriggered) {
      throw new Error('FAILED: Could not trigger restart. Check if session cookie expired or button is blocked.');
    }

    log('Monitoring reboot sequence until Online...');
    let isOnline = false;

    for (let check = 1; check <= 360; check++) {
      await page.evaluate(() => {
        const elements = Array.from(document.querySelectorAll('button, a, .btn, #confirm, #eula-accept, .btn-confirm'));
        elements.forEach(el => {
          const text = (el.innerText || el.textContent || '').trim().toLowerCase();
          if (text.includes('confirm now') || text.includes('confirm') || text.includes('accept') || text === 'yes') {
            el.click();
          }
        });
      }).catch(() => {});

      const currentStatus = await getLiveStatus(page);
      log(`[Reboot Monitor #${check}] Live Status: "${currentStatus}"`);

      if (/online/i.test(currentStatus)) {
        log('🎉 SUCCESS: Server restart complete! Fully ONLINE!');
        isOnline = true;
        break;
      }

      await randomSleep(5000, 8000);
    }

    if (!isOnline) {
      log('Warning: Reboot monitor timed out. Check Aternos manually.');
    }

  } catch (error) {
    console.error(`Automation Error: ${error.message}`);
  } finally {
    await browser.close();
    log('Browser safely closed.');
  }
}

// --- SCHEDULER SETUP ---
log('==================================================');
log('Aternos Bot Initialized!');
log('Target Server: Lets_Play_Java.aternos.me');
log('Schedule: Random time between 6:30 AM and 7:30 AM IST.');
log('==================================================');

cron.schedule('30 6 * * *', async () => {
  const randomMinutes = Math.floor(Math.random() * 60);
  log(`Cron triggered at 6:30 AM. Delaying execution by ${randomMinutes} minutes...`);
  await randomSleep(randomMinutes * 60 * 1000, randomMinutes * 60 * 1000);
  await performRestart();
}, {
  scheduled: true,
  timezone: "Asia/Kolkata" 
});

// --- TWO IMMEDIATE TEST RUNS ---
(async () => {
  log('==================================================');
  log('>>> STARTING TEST RUN 1 OF 2 UPON BOOT <<<');
  log('==================================================');
  await performRestart();

  log('Waiting 15 seconds before launching Test Run 2...');
  await randomSleep(15000, 20000);

  log('==================================================');
  log('>>> STARTING TEST RUN 2 OF 2 UPON BOOT <<<');
  log('==================================================');
  await performRestart();

  log('==================================================');
  log('Both test runs finished! Standing by for scheduled daily cron runs...');
  log('==================================================');
})();

EOF

CMD ["node", "index.js"]
