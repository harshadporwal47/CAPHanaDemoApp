'use strict';
// Copies the Fiori webapp into gen/srv/app/ so the CAP server can serve it
// as static files in production. Runs as part of the MTA before-all build step.
const { cpSync, mkdirSync } = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const src  = path.join(root, 'app', 'com.caphanademo.invoices', 'webapp');
const dst  = path.join(root, 'gen', 'srv', 'app', 'com.caphanademo.invoices');

mkdirSync(dst, { recursive: true });
cpSync(src, dst, { recursive: true });

console.log('UI files copied to gen/srv/app/com.caphanademo.invoices');
