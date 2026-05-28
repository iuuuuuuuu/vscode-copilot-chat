// _build_nologin.js - Build script for copilot-chat-nologin extension
// Usage: node _build_nologin.js [--fix-pkg-only]
const fs = require('fs');
const { execSync } = require('child_process');
const path = require('path');

const ROOT = __dirname;
const PKG_PATH = path.join(ROOT, 'package.json');

function fixPackageJson() {
    console.log('Restoring package.json from git...');
    const origPkg = execSync('git show HEAD:package.json', { cwd: ROOT, encoding: 'utf8' });
    const pkg = JSON.parse(origPkg);

    // Apply identity changes
    pkg.name = 'copilot-chat-nologin';
    pkg.displayName = 'Copilot Chat (No Login)';
    pkg.publisher = 'Community';

    // NOTE: We keep ALL vendors in languageModelChatProviders because:
    // 1. BYOK contribution registers providers for these vendors via API
    // 2. VS Code rejects registration for vendors not in package.json
    // 3. Removing vendors breaks ALL provider registration (including azure/customoai)
    // "升级" labels on unconfigured models are a VS Code UI behavior we can't prevent

    fs.writeFileSync(PKG_PATH, JSON.stringify(pkg, null, 2), 'utf8');
    console.log('package.json updated (all vendors kept)');
}

function build() {
    console.log('\nBuilding extension...');
    execSync('npm run build', { cwd: ROOT, stdio: 'inherit' });
}

function copyWasm() {
    console.log('\nCopying WASM file...');
    const src = path.join(ROOT, 'node_modules/@github/blackbird-external-ingest-utils/pkg/nodejs/external_ingest_utils_bg.wasm');
    const dest = path.join(ROOT, 'dist/external_ingest_utils_bg.wasm');
    fs.copyFileSync(src, dest);
    console.log('WASM file copied');

    // Copy tiktoken file
    const tiktokenSrc = path.join(ROOT, 'src/platform/tokenizer/node/o200k_base.tiktoken');
    const tiktokenDest = path.join(ROOT, 'dist/o200k_base.tiktoken');
    fs.copyFileSync(tiktokenSrc, tiktokenDest);
    console.log('tiktoken file copied');
}

function packageExt() {
    console.log('\nPackaging extension...');
    execSync('npm run package', { cwd: ROOT, stdio: 'inherit' });
}

const args = process.argv.slice(2);
if (args.includes('--fix-pkg-only')) {
    fixPackageJson();
} else {
    fixPackageJson();
    build();
    copyWasm();
    fixPackageJson();
    packageExt();
    console.log('\nDone!');
}
