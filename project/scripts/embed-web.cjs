// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'web', 'adspeed.js'), 'utf8').replace(/\r\n/g, '\n');
assert.equal(source.split('__ADSPEED_CONFIG__').length - 1, 1);
assert.ok(!source.includes(')ADSPEEDJS"'));
const header = '#pragma once\n\nstatic const char kAdSpeedWebScript[] = R"ADSPEEDJS('
    + source + ')ADSPEEDJS";\n';
fs.writeFileSync(path.join(root, 'AdSpeedWebScript.h'), header, 'utf8');
console.log('Embedded web/adspeed.js into AdSpeedWebScript.h');
