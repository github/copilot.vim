#!/usr/bin/env node

const minNodeVersion = 20;

function nodeVersionError() {
    const version = process.versions.node;
    const [major] = version.split('.').map(v => parseInt(v, 10));
    if (major < minNodeVersion) {
        return `Node.js ${minNodeVersion}.x is required to run GitHub Copilot but found ${version}`;
    }
}

const err = nodeVersionError();
if (err !== undefined) {
    console.error(err);
    // An exit code of X indicates a recommended minimum Node.js version of X.0.
    // Providing a recommended major version via exit code is an affordance for
    // implementations like Copilot.vim, where Neovim buries stderr in a log
    // file the user is unlikely to see.
    process.exit(minNodeVersion);
}

require('./main').main();
