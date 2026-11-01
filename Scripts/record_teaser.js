#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { chromium } = require('playwright-core');

const PROJECT_DIR = path.resolve(__dirname, '..');
const TEASER_PATH = 'file://' + path.join(PROJECT_DIR, 'teaser.html');
const TEMP_DIR = path.join('/tmp', 'autotype-record-' + Date.now());
const FINAL_MP4 = path.join(PROJECT_DIR, 'autotype-teaser.mp4');
const FINAL_WEBM = path.join(PROJECT_DIR, 'autotype-teaser.webm');

fs.mkdirSync(TEMP_DIR, { recursive: true });

async function main() {
  console.log('🚀 Starting AutoType teaser recording with millisecond audio sync...');
  console.log(`📁 Project: ${PROJECT_DIR}`);
  console.log(`🎬 Target: ${TEASER_PATH}`);

  const browser = await chromium.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: [
      '--autoplay-policy=no-user-gesture-required',
      '--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding'
    ]
  });

  const context = await browser.newContext({
    recordVideo: {
      dir: TEMP_DIR,
      size: { width: 1920, height: 1080 }
    },
    viewport: { width: 1920, height: 1080 }
  });

  const page = await context.newPage();

  console.log('⏳ Navigating to teaser page...');
  await page.goto(TEASER_PATH, { waitUntil: 'domcontentloaded' });

  // Start audio recording immediately at initial page load (T0) so audio and video share the same time origin
  await page.evaluate(() => {
    window.__autotype.setPlay(false);
    window.__autotype.audio.startRecording();
  });

  console.log('⏳ Preloading audio buffers & waiting for fonts...');
  await page.evaluate(async () => {
    await window.__autotype.audio.preload();
    await document.fonts.ready;
  });

  // Apply clean 1080p recording styles
  await page.addStyleTag({
    content: `
      body {
        padding: 0 !important;
        margin: 0 !important;
        overflow: hidden !important;
        background: #05060a !important;
      }
      body::before { display: none !important; }
      .dock { display: none !important; }
      .stage {
        position: fixed !important;
        inset: 0 !important;
        width: 1920px !important;
        height: 1080px !important;
        max-width: none !important;
        max-height: none !important;
        border-radius: 0 !important;
        border: none !important;
        box-shadow: none !important;
      }
    `
  });

  await page.waitForTimeout(400);

  console.log('🎙️ Synchronizing start timestamp and beginning playback...');
  const startPerfMs = await page.evaluate(() => {
    const t = performance.now();
    window.__autotype.goScene(0);
    window.__autotype.setPlay(true);
    const recDot = document.getElementById('recDot');
    if (recDot) recDot.classList.add('on');
    return t;
  });

  const startWallTime = Date.now();
  let lastReportedSec = -1;

  while (true) {
    await page.waitForTimeout(500);
    const state = await page.evaluate(() => {
      const isFinished = window.__autotype.isFinished();
      const s = window.__autotype.getState();
      return { isFinished, ...s };
    });

    const elapsedSec = Math.floor(state.globalT / 1000);
    const totalSec = Math.floor(state.TOTAL / 1000);

    if (elapsedSec !== lastReportedSec && elapsedSec % 5 === 0) {
      lastReportedSec = elapsedSec;
      const pct = Math.min(100, Math.round((state.globalT / state.TOTAL) * 100));
      console.log(`▶️ Progress: ${elapsedSec}s / ${totalSec}s (${pct}%) — Scene ${state.sceneIndex + 1}/6`);
    }

    if (state.isFinished || state.globalT >= state.TOTAL) {
      console.log('✅ Teaser reached the end!');
      break;
    }

    if (Date.now() - startWallTime > 90000) {
      console.warn('⚠️ Safety timeout reached, stopping...');
      break;
    }
  }

  // Allow outro animation to settle
  await page.waitForTimeout(1500);

  const endPerfMs = await page.evaluate(() => performance.now());

  console.log('⏹️ Stopping audio recording...');
  const audioDataUrl = await page.evaluate(async () => {
    return await window.__autotype.audio.stopRecording();
  });

  const rawAudioPath = path.join(TEMP_DIR, 'audio.webm');
  if (audioDataUrl) {
    const base64Data = audioDataUrl.split(',')[1];
    fs.writeFileSync(rawAudioPath, Buffer.from(base64Data, 'base64'));
    console.log(`🎵 Audio saved: ${rawAudioPath} (${fs.statSync(rawAudioPath).size} bytes)`);
  } else {
    throw new Error('No audio data captured!');
  }

  // Close context to finish writing video file
  await context.close();
  await browser.close();

  // Find recorded video file
  const videoFiles = fs.readdirSync(TEMP_DIR).filter(f => f.endsWith('.webm') && f !== 'audio.webm');
  if (!videoFiles.length) {
    throw new Error('No video file produced by Playwright!');
  }
  const rawVideoPath = path.join(TEMP_DIR, videoFiles[0]);
  console.log(`📹 Raw video saved: ${rawVideoPath} (${fs.statSync(rawVideoPath).size} bytes)`);

  const startSec = (startPerfMs / 1000).toFixed(3);
  const durationSec = ((endPerfMs - startPerfMs) / 1000).toFixed(3);
  console.log(`⏱️ Exact sync: Start at ${startSec}s, Duration: ${durationSec}s`);

  console.log('🎞️ Merging video + keyboard sound into final MP4 & WebM with ffmpeg...');

  // 1. Export 1080p MP4 (H.264 + AAC)
  execSync(
    `ffmpeg -y ` +
    `-ss ${startSec} -t ${durationSec} -i "${rawVideoPath}" ` +
    `-ss ${startSec} -t ${durationSec} -i "${rawAudioPath}" ` +
    `-c:v libx264 -pix_fmt yuv420p -preset slow -crf 18 ` +
    `-c:a aac -b:a 192k -ar 48000 ` +
    `-movflags +faststart ` +
    `"${FINAL_MP4}"`,
    { stdio: 'inherit' }
  );

  // 2. Export 1080p WebM (VP9 + Opus)
  execSync(
    `ffmpeg -y ` +
    `-ss ${startSec} -t ${durationSec} -i "${rawVideoPath}" ` +
    `-ss ${startSec} -t ${durationSec} -i "${rawAudioPath}" ` +
    `-c:v libvpx-vp9 -b:v 2M -crf 24 ` +
    `-c:a libopus -b:a 128k ` +
    `"${FINAL_WEBM}"`,
    { stdio: 'inherit' }
  );

  console.log('\n🎉 DONE!');
  console.log(`📁 MP4:  ${FINAL_MP4} (${(fs.statSync(FINAL_MP4).size / (1024 * 1024)).toFixed(2)} MB)`);
  console.log(`📁 WebM: ${FINAL_WEBM} (${(fs.statSync(FINAL_WEBM).size / (1024 * 1024)).toFixed(2)} MB)`);
}

main().catch(err => {
  console.error('❌ Error recording teaser:', err);
  process.exit(1);
});
