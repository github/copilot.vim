#!/usr/bin/env node

const minMajor = 22;
const minMinor = 0;

function main() {
    const argv = process.argv.slice(2);
    const version = process.versions.node;
    const [major, minor] = version.split('.').map(v => parseInt(v, 10));
    if (major > minMajor || (major === minMajor && minor >= minMinor)) {
        return require('./main').main();
    }

    if (!argv.includes('--node-ipc')) {
        const path = require('path');
        const root = path.join(__dirname, '..');
        const bin = path.join(
            `copilot-language-server-${process.platform}-${process.arch}`,
            `copilot-language-server${process.platform === 'win32' ? '.exe' : ''}`
        );
        const cp = require('child_process');
        const result1 = cp.spawnSync(path.join(root, 'node_modules', '@github', bin), argv, {stdio: 'inherit'});
        if (typeof result1.status === 'number') process.exit(result1.status);
        const result2 = cp.spawnSync(path.join(root, '..', bin), argv, {stdio: 'inherit'});
        if (typeof result2.status === 'number') process.exit(result2.status);
    }
    console.error(`Node.js ${minMajor}.${minMinor} is required to run GitHub Copilot but found ${version}`);
    // An exit code of X indicates a recommended minimum Node.js version of X.0.
    // Providing a recommended major version via exit code is an affordance for
    // implementations like Copilot.vim, where Neovim buries stderr in a log
    // file the user is unlikely to see.
    process.exit(minMajor + (minMinor ? 2 : 0));
}

main();
