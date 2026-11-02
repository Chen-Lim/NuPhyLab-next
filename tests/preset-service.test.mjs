import test from "node:test";
import assert from "node:assert/strict";
import { createPresets } from "../shared/presets.mjs";
import { layout } from "../shared/layout.mjs";
import { fakeService, until } from "./helpers/fake-service.mjs";

test("every built-in preset can be sent, paused and saved through the real service", async t => {
  const service = await fakeService(t);
  await service.command({ op: "settings", settings: { brightness: 100, codexEnabled: false, quotaSideEnabled: false } });
  for (const preset of createPresets(layout)) {
    const scene = { name: preset.name, colors: preset.colors, animation: preset.animation,
      ...(preset.trigger?{trigger:preset.trigger}:{}) };
    const saved = await service.command({ op: "saveScene", scene });
    assert.equal(saved.ok, true, preset.id);
    assert.notEqual(saved.result.savedScene.id, preset.id, "built-ins must save as independent user scenes");
    assert.equal(saved.result.savedScene.animation.effect, preset.animation.effect);
    if (preset.animation.frames)
      assert.equal(saved.result.savedScene.animation.frames.length, preset.animation.frames.length);
    const before = (await service.state()).playback.framesSent;
    const result = await service.command({
      op: scene.trigger?'triggerArm':"play",
      colors: scene.colors,
      animation: scene.animation,
      ...(scene.trigger?{trigger:scene.trigger}:{}),
    });
    assert.equal(result.ok, true, preset.id);
    if(scene.trigger){
      assert.deepEqual(saved.result.savedScene.trigger,scene.trigger);
      assert.equal((await service.state()).trigger.armed,true);
      assert.ok((await service.state()).colors.every(color=>color==='#000000'));
      await service.command({op:'triggerFire',code:'KeyG'});
      await until(service.state,state=>state.colors.some(color=>color!=='#000000'),'typing preset did not react');
      await until(service.state,state=>!state.trigger.flashing,'typing tail did not finish');
      assert.equal((await service.state()).trigger.armed,true,'tail completion keeps listening');
    } else if (preset.animation.effect !== "static") {
      await until(service.state, state => state.playback.framesSent >= before + 3, `${preset.id} did not advance`);
      assert.equal((await service.command({ op: "pause" })).ok, true);
      assert.equal((await service.state()).playback.playing, false);
    }
    assert.equal((await service.state()).colors[83], "#000000", preset.id);
    assert.equal((await service.command({ op: "stop" })).ok, true);
    assert.equal((await service.state()).device.armed, false);
  }
  const state = await service.state();
  assert.equal(state.scenes.length, createPresets(layout).length);
  assert.equal(new Set(state.scenes.map(scene => scene.id)).size, state.scenes.length);
});
