const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../../..');
const playerSource = fs.readFileSync(path.join(root, 'pkg/emscripten/libretro/libretro.js'), 'utf8');
const configPath = '/home/web_user/retroarch/userdata/retroarch.cfg';

async function loadPlayer({base44 = false, savedCore, config, artifacts} = {}) {
   const files = new Map(config === undefined ? [] : [[configPath, config]]);
   const storage = new Map(savedCore ? [['core', savedCore]] : []);
   const elements = new Map();
   const clicks = new Map();
   const imports = [];
   const errors = [];
   const writes = [];
   const runs = [];
   let ready;
   let mounted = false;
   artifacts = artifacts || (base44 ? ['dummy'] : ['gambatte', 'fceumm']);

   function element(id) {
      if (!elements.has(id)) {
         elements.set(id, {disabled: true, children: [], appendChild(child) { this.children.push(child); }});
      }
      return elements.get(id);
   }

   function $(selector) {
      if (typeof selector === 'function') {
         ready = selector;
         return;
      }
      const chain = {
         click(callback) { clicks.set(selector, callback); return chain; },
         removeAttr(name) { delete element(selector.slice(1))[name]; return chain; },
         text(value) { return value === undefined ? '' : chain; }
      };
      for (const method of ['addClass', 'removeClass', 'hide', 'show', 'change', 'tooltip', 'slideToggle', 'toggle']) {
         chain[method] = () => chain;
      }
      return chain;
   }

   const context = vm.createContext({
      $, Uint8Array,
      console: {log() {}, error(...args) { errors.push(args); }},
      alert(message) { errors.push(message); },
      document: {
         getElementById: element,
         createElement() { return {dataset: {}, classList: {add() {}}}; }
      },
      window: {addEventListener() {}},
      localStorage: {
         getItem(key) { return storage.get(key) || null; },
         setItem(key, value) { storage.set(key, value); }
      }
   });
   const coreList = base44 ? '.base44/core_list.js' : 'pkg/emscripten/libretro/core_list.js';
   vm.runInContext(fs.readFileSync(path.join(root, coreList), 'utf8'), context);
   const script = new vm.Script(playerSource, {
      filename: 'libretro.js',
      async importModuleDynamically(specifier) {
         imports.push(specifier);
         assert.ok(artifacts.some(core => specifier === './' + core + '_libretro.js'), 'Missing artifact: ' + specifier);
         const module = new vm.SyntheticModule(['default'], function() {
            this.setExport('default', async options => ({
               ...options,
               FS: {
                  analyzePath(file) { assert.ok(mounted); return {exists: files.has(file)}; },
                  writeFile(file, value) { assert.ok(mounted); writes.push(file); files.set(file, value); }
               },
               callMain(args) { runs.push(Array.from(args)); }
            }));
         }, {context});
         await module.link(() => {});
         await module.evaluate();
         return module;
      }
   });
   script.runInContext(context);
   // Exercise the real startup/Run path with filesystem readiness and WASM mocked.
   context.idbfsInit = context.zipfsInit = context.xhrfsInit = () => context.appInitialized();
   context.finishFileSystemSetup = () => { mounted = true; };
   ready();
   await new Promise(setImmediate);
   assert.deepEqual(errors, []);
   assert.equal(context.initializationCount, 4);
   assert.ok(!element('btnRun').disabled);

   return {
      files, storage, imports, writes, runs,
      cores: element('core-selector').children.map(child => child.dataset.core),
      run() { clicks.get('#btnRun')(); }
   };
}

test('normal player keeps gambatte as its first-visit default and the normal catalog', async () => {
   const player = await loadPlayer();
   assert.deepEqual(player.imports, ['./gambatte_libretro.js']);
   assert.ok(player.cores.includes('gambatte') && player.cores.includes('fceumm'));
   assert.ok(!player.cores.includes('dummy'));
   player.run();
   assert.equal(player.files.has(configPath), false);
   assert.deepEqual(player.writes, []);
   assert.equal(player.runs.length, 1);
});

test('normal single-core deployment keeps the saved core selection', async () => {
   const player = await loadPlayer({savedCore: 'fceumm', artifacts: ['fceumm']});
   assert.deepEqual(player.imports, ['./fceumm_libretro.js']);
   player.run();
   assert.deepEqual(player.runs, [['-v', '--menu', '-c', configPath]]);
});

for (const savedCore of [undefined, 'dummy', 'gambatte', 'missing-core']) {
   test('Base44 initializes only dummy with saved core ' + savedCore, async () => {
      const player = await loadPlayer({base44: true, savedCore});
      assert.deepEqual(player.cores, ['dummy']);
      assert.deepEqual(player.imports, ['./dummy_libretro.js']);
      assert.equal(player.storage.get('core'), savedCore);
      player.run();
      assert.equal(player.files.get(configPath), 'menu_driver = "rgui"\n');
      assert.equal(player.runs.length, 1);
      const updated = 'menu_driver = "rgui"\naudio_volume = "-8.0"\n';
      player.files.set(configPath, updated);
      player.run();
      assert.equal(player.files.get(configPath), updated);
      assert.deepEqual(player.writes, [configPath]);
   });
}

for (const base44 of [false, true]) {
   for (const config of ['', '# User settings\nmenu_driver = "ozone"\naudio_volume = "-12.0"\ninput_player1_a = "z"\n']) {
      test((base44 ? 'Base44' : 'normal player') + ' preserves existing ' + (config ? 'custom' : 'empty') + ' config on repeated Run', async () => {
         const player = await loadPlayer({base44, config});
         player.run();
         player.run();
         assert.equal(player.files.get(configPath), config);
         assert.deepEqual(player.writes, []);
         assert.equal(player.runs.length, 2);
      });
   }
}
