/**
 * 小红书内容图截图脚本
 * 用法：NODE_PATH=<playwright_path> node screenshot.cjs <html_file> [output_dir]
 *
 * - html_file: 包含多个 .page 元素的 HTML 文件路径
 * - output_dir: 输出目录（默认为 HTML 文件所在目录）
 *
 * 输出：逐页截取每个 .page 元素，保存为 PNG
 */

const { chromium } = require('playwright');
const { resolve, dirname, basename } = require('path');

(async () => {
    const htmlFile = resolve(process.argv[2]);
    const outputDir = process.argv[3] ? resolve(process.argv[3]) : dirname(htmlFile);

    // Extract base name for output files (remove extension and temp prefix)
    let baseName = basename(htmlFile, '.html').replace(/^xhs-content-/, 'xhs-');

    const browser = await chromium.launch();
    const page = await browser.newPage({
        viewport: { width: 1080, height: 10000 }
    });

    await page.goto(`file://${htmlFile}`);
    await page.waitForLoadState('networkidle');
    // Extra wait for fonts to load
    await page.waitForTimeout(2000);

    const pages = await page.locator('.page').all();
    const count = pages.length;
    console.log(`Found ${count} pages`);

    const outputFiles = [];

    for (let i = 0; i < count; i++) {
        const outputFile = resolve(outputDir, `${baseName}-page-${i + 1}.png`);
        await pages[i].screenshot({ path: outputFile });
        outputFiles.push(outputFile);
        console.log(`[${i + 1}/${count}] Saved: ${outputFile}`);
    }

    await browser.close();

    // Output JSON summary for programmatic consumption
    console.log(JSON.stringify({ total: count, files: outputFiles }));
    console.log('Done!');
})().catch(err => {
    console.error('Screenshot error:', err.message);
    process.exit(1);
});
