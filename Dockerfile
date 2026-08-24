FROM mcr.microsoft.com/playwright:v1.62.1-jammy

WORKDIR /app

# 1. Install Playwright, stealth plugins, and node-cron
RUN npm init -y && npm install playwright@1.62.1 playwright-extra puppeteer-extra-plugin-stealth node-cron

# 2. Production script with crash prevention & memory optimization
RUN cat <<'EOF' > index.js
const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();
chromium.use(stealth);

const cron = require('node-cron');

function log(message) {
  const time = new Date().toISOString().substring(11, 19);
  console.log(`[${time}] ${message}`);
}

const randomSleep = (minMs, maxMs) => {
  const delay = Math.floor(Math.random() * (maxMs - minMs + 1)) + minMs;
  return new Promise(resolve => setTimeout(resolve, delay));
};

async function humanClick(page, selector) {
  try {
    const element = await page.$(selector);
    if (element && await element.isVisible()) {
      const box = await element.boundingBox();
      if (box) {
        const targetX = box.x + box.width * (0.2 + Math.random() * 0.6);
        const targetY = box.y + box.height * (0.2 + Math.random() * 0.6);

        await page.mouse.move(targetX - 30 + Math.random() * 60, targetY - 30 + Math.random() * 60, { steps: 8 });
        await randomSleep(150, 350);
        await page.mouse.move(targetX, targetY, { steps: 10 });
        await randomSleep(100, 250);
        await page.mouse.click(targetX, targetY);
        return true;
      }
    }
  } catch (err) {
    // Failover to evaluate
  }
  return false;
}

async function performRestart() {
  const sessionCookie = "tR5AEALhfCJnR1ddaZhqQ2nJYRGNAq5yM5OCes2a24w82Fd5P4Grxs9xbEboN06Nrje5GOwObVkOGuzvMUVBgnlyFXXAnlJQQlLy";
  const serverCookie = "48yt9NqKp60s1DRO";
  const targetServerName = "Lets_Play_Java.aternos.me";

  log('--- INITIATING STEALTH RESTART SEQUENCE ---');
  log('Launching optimized stealth browser engine...');

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage', // Fixes "target crashed" / SHM memory exhaustion in Docker
      '--disable-gpu',
      '--no-zygote',
      '--single-process',
      '--disable-blink-features=AutomationControlled',
      '--disable-infobars',
      '--ignore-certificate-errors'
    ]
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    viewport: { width: 1920, height: 1080 },
    locale: 'en-US',
    timezoneId: 'Asia/Kolkata',
    javaScriptEnabled: true
  });

  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    window.chrome = { runtime: {} };
    Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
    Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
  });

  await context.addCookies([
    { name: 'ATERNOS_SESSION', value: sessionCookie, domain: '.aternos.org', path: '/', httpOnly: true, secure: true, sameSite: 'Lax' },
    { name: 'ATERNOS_SERVER', value: serverCookie, domain: '.aternos.org', path: '/', httpOnly: true, secure: true, sameSite: 'Lax' }
  ]);

  const page = await context.newPage();

  // Abort heavy media/font requests that cause container memory leaks
  await page.route('**/*.{png,jpg,jpeg,gif,svg,woff,woff2,mp4,webm}', route => route.abort());

  try {
    log('Navigating to Aternos server selection / dashboard...');
    await page.goto('https://aternos.org/servers/', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await randomSleep(3000, 5000);

    if (page.url().includes('/go')) {
      throw new Error('SESSION EXPIRED: Please update your ATERNOS_SESSION cookie.');
    }

    // Target server selection logic
    const foundTarget = await page.evaluate((serverName) => {
      const cards = Array.from(document.querySelectorAll('.server-body, .servercard, .server-name'));
      for (const card of cards) {
        if (card.innerText.toLowerCase().includes(serverName.toLowerCase())) {
          card.click();
          return true;
        }
      }
      return false;
    }, targetServerName).catch(() => false);

    if (foundTarget) {
      log(`Target server "${targetServerName}" clicked on server list.`);
      await randomSleep(3000, 5000);
    } else {
      log(`Navigating directly to server dashboard...`);
      await page.goto('https://aternos.org/server/', { waitUntil: 'domcontentloaded', timeout: 60000 });
      await randomSleep(3000, 5000);
    }

    log('Triggering Restart sequence...');
    let restartTriggered = false;

    for (let attempt = 1; attempt <= 10; attempt++) {
      let clicked = await humanClick(page, '#restart');
      if (!clicked) clicked = await humanClick(page, '#start');

      if (!clicked) {
        await page.evaluate(() => {
          const restart = document.querySelector('#restart');
          const start = document.querySelector('#start');
          if (restart && restart.offsetParent !== null) restart.click();
          else if (start && start.offsetParent !== null) start.click();
        }).catch(() => {});
      }

      await randomSleep(1000, 2500);

      // Dismiss confirmation modals
      await page.evaluate(() => {
        const buttons = Array.from(document.querySelectorAll('button, a, .btn, #confirm, .btn-danger, .btn-confirm'));
        buttons.forEach(b => {
          const text = (b.innerText || b.textContent || '').trim().toLowerCase();
          if (text === 'yes' || text.includes('confirm') || text.includes('accept')) {
            b.click();
          }
        });
      }).catch(() => {});

      const currentStatus = await page.evaluate(() => {
        const el = document.querySelector('.status-label-body, .server-status-label, .status');
        return el ? el.innerText.trim().toLowerCase() : 'unknown';
      }).catch(() => 'unknown');

      log(`[Attempt ${attempt}/10] Status: "${currentStatus}"`);

      if (/saving|stopping|restarting|preparing|loading|starting|queue|min/i.test(currentStatus)) {
        log(`SUCCESS: Reboot sequence verified! Server status is now "${currentStatus}".`);
        restartTriggered = true;
        break;
      }

      await randomSleep(3000, 5500);
    }

    if (!restartTriggered) {
      throw new Error('FAILED: Could not trigger restart on target server.');
    }

    log('Monitoring reboot state...');
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

      const currentStatus = await page.evaluate(() => {
        const el = document.querySelector('.status-label-body, .server-status-label, .status');
        return el ? el.innerText.trim().toLowerCase() : 'unknown';
      }).catch(() => 'unknown');

      log(`[Monitor #${check}] Status: "${currentStatus}"`);

      if (/online/i.test(currentStatus)) {
        log('🎉 SUCCESS: Server restart complete! Fully ONLINE!');
        isOnline = true;
        break;
      }

      await randomSleep(4500, 7500);
    }

    if (!isOnline) {
      log('Warning: Reboot monitor finished without confirming online status.');
    }

  } catch (error) {
    console.error(`Automation Error: ${error.message}`);
  } finally {
    await browser.close().catch(() => {});
    log('Browser safely closed. Standing by for next scheduled run...');
  }
}

// --- SCHEDULER SETUP ---
log('==================================================');
log('Aternos Stealth Bot Initialized!');
log('Target Server: Lets_Play_Java.aternos.me');
log('Cron Scheduled: Triggers at 6:30 AM IST with a randomized delay (6:30 AM - 7:30 AM IST)');
log('==================================================');

cron.schedule('30 6 * * *', async () => {
  const randomMinutes = Math.floor(Math.random() * 60);
  log(`Cron triggered at 6:30 AM. Waiting a randomized ${randomMinutes} minutes (Target time: 6:${30 + randomMinutes} AM)...`);
  await randomSleep(randomMinutes * 60 * 1000, randomMinutes * 60 * 1000);
  await performRestart();
}, {
  scheduled: true,
  timezone: "Asia/Kolkata"
});

// IMMEDIATE TEST RUN UPON CONTAINER BOOT
log('Triggering an immediate test run right now upon deploy...');
performRestart();

EOF

CMD ["node", "index.js"]
