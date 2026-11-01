#!/usr/bin/env node
const path = require('path');
const { chromium } = require('playwright-core');

const OUTPUT_PATH = path.resolve(__dirname, '..', 'og-preview.png');

const html = `<!DOCTYPE html>
<html lang="fa">
<head>
<meta charset="UTF-8">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Vazirmatn:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body {
    width: 1200px;
    height: 630px;
    margin: 0;
    padding: 0;
    background: #08090c;
    color: #f1f3f6;
    font-family: "Vazirmatn", -apple-system, BlinkMacSystemFont, sans-serif;
    overflow: hidden;
    -webkit-font-smoothing: antialiased;
  }
  .canvas {
    width: 1200px;
    height: 630px;
    position: relative;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    padding: 44px 54px;
    direction: rtl;
  }
  .canvas::before {
    content: "";
    position: absolute;
    inset: 0;
    background-image:
      linear-gradient(to right, rgba(255,255,255,0.032) 1px, transparent 1px),
      linear-gradient(to bottom, rgba(255,255,255,0.032) 1px, transparent 1px);
    background-size: 60px 60px;
    mask-image: radial-gradient(120% 100% at 50% 20%, #000 30%, transparent 90%);
    -webkit-mask-image: radial-gradient(120% 100% at 50% 20%, #000 30%, transparent 90%);
    pointer-events: none;
  }
  .glow-1 {
    position: absolute;
    width: 560px;
    height: 560px;
    left: -120px;
    top: -140px;
    background: radial-gradient(circle, rgba(63,159,216,0.18) 0%, rgba(92,184,148,0.06) 45%, transparent 70%);
    pointer-events: none;
  }
  .glow-2 {
    position: absolute;
    width: 520px;
    height: 520px;
    right: -100px;
    bottom: -180px;
    background: radial-gradient(circle, rgba(157,139,214,0.14) 0%, rgba(63,159,216,0.05) 50%, transparent 70%);
    pointer-events: none;
  }

  .top-bar {
    position: relative;
    z-index: 2;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .brand-mark {
    width: 42px;
    height: 42px;
    border-radius: 10px;
    background: linear-gradient(135deg, rgba(63,159,216,0.22), rgba(63,159,216,0.06));
    border: 1px solid rgba(124,192,232,0.38);
    display: flex;
    align-items: center;
    justify-content: center;
    color: #7cc0e8;
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
  }
  .brand-name {
    font-family: "JetBrains Mono", monospace;
    font-size: 25px;
    font-weight: 700;
    letter-spacing: -0.02em;
    color: #f1f3f6;
  }
  .beta-pill {
    font-family: "JetBrains Mono", monospace;
    font-size: 11.5px;
    font-weight: 700;
    letter-spacing: 0.08em;
    padding: 4px 10px;
    border-radius: 999px;
    background: rgba(210,155,60,0.15);
    border: 1px solid rgba(210,155,60,0.45);
    color: #f0be63;
  }
  .meta-pills {
    display: flex;
    align-items: center;
    gap: 10px;
    direction: ltr;
  }
  .pill {
    font-family: "JetBrains Mono", monospace;
    font-size: 12.5px;
    font-weight: 500;
    padding: 6px 13px;
    border-radius: 8px;
    background: rgba(255,255,255,0.045);
    border: 1px solid rgba(255,255,255,0.11);
    color: #b4bece;
    display: flex;
    align-items: center;
    gap: 7px;
  }
  .pill .dot-ok {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #5cb894;
    box-shadow: 0 0 10px #5cb894;
  }

  .main-grid {
    position: relative;
    z-index: 2;
    display: grid;
    grid-template-columns: 1.12fr 0.88fr;
    gap: 36px;
    align-items: center;
    margin: 8px 0;
  }

  .right-col {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .headline {
    font-size: 44px;
    font-weight: 900;
    line-height: 1.28;
    letter-spacing: -0.015em;
    color: #ffffff;
  }
  .headline .accent {
    background: linear-gradient(90deg, #7cc0e8 0%, #5cb894 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .subhead {
    font-size: 18px;
    line-height: 1.72;
    color: #a9b3c2;
    font-weight: 400;
  }
  .subhead code {
    font-family: "JetBrains Mono", monospace;
    font-size: 14.5px;
    background: rgba(63,159,216,0.14);
    border: 1px solid rgba(63,159,216,0.3);
    color: #7cc0e8;
    padding: 2px 8px;
    border-radius: 5px;
    direction: ltr;
    display: inline-block;
  }

  .features {
    display: flex;
    flex-wrap: wrap;
    gap: 9px;
    margin-top: 4px;
  }
  .feat {
    font-size: 13px;
    font-weight: 600;
    padding: 7px 12px;
    border-radius: 8px;
    background: #10131a;
    border: 1px solid rgba(255,255,255,0.1);
    color: #dbe1ea;
    display: flex;
    align-items: center;
    gap: 7px;
  }
  .feat span.ic {
    color: #5cb894;
    font-weight: 800;
  }
  .feat.ai {
    border-color: rgba(157,139,214,0.38);
    background: rgba(157,139,214,0.11);
    color: #e4def7;
  }
  .feat.ai span.ic {
    color: #b7a6ea;
  }

  .showcase-card {
    background: linear-gradient(180deg, #11151e 0%, #0b0e14 100%);
    border: 1px solid rgba(255,255,255,0.14);
    border-radius: 14px;
    box-shadow: 0 24px 60px rgba(0,0,0,0.65), 0 0 0 1px rgba(63,159,216,0.08);
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
  .card-header {
    background: #161b26;
    padding: 11px 16px;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    display: flex;
    align-items: center;
    justify-content: space-between;
    direction: ltr;
  }
  .win-dots {
    display: flex;
    gap: 7px;
  }
  .win-dots span {
    width: 11px;
    height: 11px;
    border-radius: 50%;
  }
  .win-dots .r { background: #ff5f57; }
  .win-dots .y { background: #febc2e; }
  .win-dots .g { background: #28c840; }
  .card-title {
    font-family: "JetBrains Mono", monospace;
    font-size: 11.5px;
    color: #8c98a9;
  }
  .card-live {
    font-size: 11.5px;
    font-weight: 600;
    color: #5cb894;
    font-family: "Vazirmatn", sans-serif;
    direction: rtl;
  }

  .card-body {
    padding: 16px 18px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .conv-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.075);
    border-radius: 10px;
    padding: 10px 14px;
    direction: ltr;
  }
  .conv-row.highlight {
    background: rgba(63,159,216,0.09);
    border-color: rgba(63,159,216,0.32);
  }
  .conv-row.ai-row {
    background: rgba(157,139,214,0.09);
    border-color: rgba(157,139,214,0.3);
  }
  .typed-keys {
    font-family: "JetBrains Mono", monospace;
    font-size: 14px;
    font-weight: 600;
    color: #99a3b2;
    background: #080a0f;
    border: 1px solid rgba(255,255,255,0.12);
    padding: 4px 10px;
    border-radius: 6px;
  }
  .typed-persian {
    font-family: "Vazirmatn", sans-serif;
    font-size: 13.5px;
    font-weight: 600;
    color: #d7deea;
    background: #080a0f;
    border: 1px solid rgba(157,139,214,0.3);
    padding: 4px 10px;
    border-radius: 6px;
    direction: rtl;
  }
  .typed-persian b {
    color: #c3b5ed;
  }
  .conv-arrow {
    font-family: "JetBrains Mono", monospace;
    color: #3f9fd8;
    font-size: 16px;
    font-weight: 700;
  }
  .conv-out {
    font-size: 16.5px;
    font-weight: 700;
    color: #f1f3f6;
    direction: rtl;
    display: flex;
    align-items: center;
    gap: 7px;
  }
  .conv-out.en {
    font-family: "JetBrains Mono", monospace;
    font-size: 13.5px;
    color: #5cb894;
    direction: ltr;
  }
  .conv-tag {
    font-family: "Vazirmatn", sans-serif;
    font-size: 10.5px;
    font-weight: 600;
    padding: 2px 7px;
    border-radius: 5px;
    background: rgba(92,184,148,0.14);
    color: #5cb894;
  }
  .conv-tag.blue {
    background: rgba(63,159,216,0.16);
    color: #7cc0e8;
  }
  .conv-tag.purple {
    background: rgba(157,139,214,0.18);
    color: #c3b5ed;
  }

  .bottom-bar {
    position: relative;
    z-index: 2;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-top: 16px;
    border-top: 1px solid rgba(255,255,255,0.09);
  }
  .stats-row {
    display: flex;
    align-items: center;
    gap: 26px;
  }
  .stat-item {
    display: flex;
    align-items: baseline;
    gap: 7px;
  }
  .stat-item b {
    font-size: 18.5px;
    font-weight: 800;
    color: #7cc0e8;
  }
  .stat-item span {
    font-size: 13px;
    color: #8f9baa;
  }
  .repo-badge {
    direction: ltr;
    font-family: "JetBrains Mono", monospace;
    font-size: 13px;
    color: #d0d8e4;
    background: rgba(255,255,255,0.05);
    border: 1px solid rgba(255,255,255,0.13);
    padding: 7px 14px;
    border-radius: 8px;
    display: flex;
    align-items: center;
    gap: 8px;
  }
</style>
</head>
<body>
<div class="canvas">
  <div class="glow-1"></div>
  <div class="glow-2"></div>

  <div class="top-bar">
    <div class="brand">
      <div class="brand-mark">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><rect x="2.5" y="5.5" width="19" height="13" rx="2.5"/><path d="M6.5 9.5h.01M10 9.5h.01M13.5 9.5h.01M17 9.5h.01M8.5 13.5h7"/></svg>
      </div>
      <span class="brand-name">AutoType</span>
      <span class="beta-pill">BETA · v1.2</span>
    </div>

    <div class="meta-pills">
      <div class="pill"><span class="dot-ok"></span> macOS 14+ Native IME</div>
      <div class="pill">ISIRI 2901</div>
      <div class="pill">Open Source · MIT</div>
    </div>
  </div>

  <div class="main-grid">
    <div class="right-col">
      <div class="headline">
        چیدمان انگلیسی را عوض نکن.<br>
        <span class="accent">زبان را خودش تشخیص می‌دهد.</span>
      </div>
      <div class="subhead">
        ورودی هوشمند و بومی macOS برای تایپ فارسی روی کیبورد انگلیسی بدون نیاز به <code>Cmd + Space</code> — همراه با حفظ خودکار کد و اصطلاحات فنی، نیم‌فاصلهٔ دقیق و دستیار هوش مصنوعی درجا.
      </div>
      <div class="features">
        <div class="feat"><span class="ic">✓</span> تشخیص کلمه‌به‌کلمه فارسی و انگلیسی</div>
        <div class="feat"><span class="ic">✓</span> نیم‌فاصله و اصلاح جابه‌جایی حروف</div>
        <div class="feat ai"><span class="ic">✦</span> ترجمه و ویرایش نگارشی درجا با Enter</div>
        <div class="feat"><span class="ic">✓</span> اعداد هوشمند انگلیسی در فرم‌ها</div>
      </div>
    </div>

    <div class="showcase-card">
      <div class="card-header">
        <div class="win-dots"><span class="r"></span><span class="y"></span><span class="g"></span></div>
        <div class="card-title">US QWERTY → Live Conversion</div>
        <div class="card-live">● تشخیص زنده</div>
      </div>
      <div class="card-body">
        <div class="conv-row highlight">
          <span class="typed-keys">sghl ;jhfih</span>
          <span class="conv-arrow">→</span>
          <span class="conv-out"><span class="conv-tag blue">فارسی + نیم‌فاصله</span>سلام کتاب‌ها</span>
        </div>
        <div class="conv-row">
          <span class="typed-keys">ldv,n</span>
          <span class="conv-arrow">→</span>
          <span class="conv-out"><span class="conv-tag">تشخیص خودکار</span>می‌رود</span>
        </div>
        <div class="conv-row">
          <span class="typed-keys">git push origin main</span>
          <span class="conv-arrow">→</span>
          <span class="conv-out en">git push origin main</span>
        </div>
        <div class="conv-row ai-row">
          <span class="typed-persian">گزارش آماده است <b>ترجمه</b> ⏎</span>
          <span class="conv-arrow">→</span>
          <span class="conv-out en"><span class="conv-tag purple">AI</span>The report is ready.</span>
        </div>
      </div>
    </div>
  </div>

  <div class="bottom-bar">
    <div class="stats-row">
      <div class="stat-item"><b>۳۹۵٬۶۰۶</b><span>واژهٔ فارسی</span></div>
      <div class="stat-item"><b>۲۳۸٬۱۸۲</b><span>واژهٔ انگلیسی</span></div>
      <div class="stat-item"><b>۶۱۰+</b><span>اصطلاح فنی و کد</span></div>
      <div class="stat-item"><b>تست زنده</b><span>در مرورگر</span></div>
    </div>
    <div class="repo-badge">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 00-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0019 6.08 5.07 5.07 0 0018.91 3S17.73 2.63 15 4.48a13.38 13.38 0 00-7 0C5.27 2.63 4.09 3 4.09 3A5.07 5.07 0 004 6.08a5.44 5.44 0 00-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 009 18.13V22"/></svg>
      github.com/gdariushahmadi/autotype-mac
    </div>
  </div>
</div>
</body>
</html>`;

async function main() {
  const browser = await chromium.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true
  });
  const context = await browser.newContext({
    viewport: { width: 1200, height: 630 },
    deviceScaleFactor: 2
  });
  const page = await context.newPage();
  await page.setContent(html, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(300);
  await page.screenshot({ path: OUTPUT_PATH, type: 'png' });
  await browser.close();
  console.log(`✅ Generated ${OUTPUT_PATH}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
