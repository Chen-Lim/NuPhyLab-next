// Runtime form of ui/src/music/model.ts; parity is checked by music-model-parity.test.mjs.
export const instruments = [['piano', '三角钢琴', 'Salamander · 采样'], ['electric', '电钢琴', '温暖的 FM 钟音'], ['warm', '柔和合成器', '双振荡器 · 暖色'], ['pluck', '拨弦', '清脆 · 短音'], ['bass', '合成贝斯', '低频 · 圆润'], ['guitar', '过载吉他', '双振荡器 · 失真']];
export const drums = ['底鼓', '军鼓', '拍手', '闭镲', '开镲', '低嗵', '高嗵', '叮音'];
export const drumKeys = ['KeyQ', 'KeyW', 'KeyE', 'KeyR', 'KeyA', 'KeyS', 'KeyD', 'KeyF'];
export const pianoKeys = ['KeyZ', 'KeyS', 'KeyX', 'KeyD', 'KeyC', 'KeyV', 'KeyG', 'KeyB', 'KeyH', 'KeyN', 'KeyJ', 'KeyM', 'KeyQ', 'Digit2', 'KeyW', 'Digit3', 'KeyE', 'KeyR', 'Digit5', 'KeyT', 'Digit6', 'KeyY', 'Digit7', 'KeyU'];
export const keyLabels = ['Z', 'S', 'X', 'D', 'C', 'V', 'G', 'B', 'H', 'N', 'J', 'M', 'Q', '2', 'W', '3', 'E', 'R', '5', 'T', '6', 'Y', '7', 'U'];
export const clipNames = ['晨光', '缓慢漂浮', '玻璃雨', '微光', '低音漫步', '都市脉搏', '轻敲', '星尘'];
export const scales = { chromatic: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], major: [0, 2, 4, 5, 7, 9, 11], minor: [0, 2, 3, 5, 7, 8, 10], pentatonic: [0, 2, 4, 7, 9] };
export const noteNames = ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];
export const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
export const wrap = (x, n) => ((x % n) + n) % n;
export function noteName(n) { return noteNames[wrap(n, 12)] + (Math.floor(n / 12) - 1); }
export function mappedNotes(index, s) {
    const intervals = scales[s.scale];
    const base = 12 * (s.octave + 1) + s.root;
    const n = s.scale === 'chromatic' ? base + index : base + 12 * Math.floor(index / intervals.length) + intervals[index % intervals.length];
    if (!s.chord)
        return [clamp(n, 21, 108)];
    if (s.scale === 'chromatic')
        return [...new Set([n, n + 4, n + 7].map(x => clamp(x, 21, 108)))];
    return [0, 2, 4].map(offset => { const i = index + offset; return base + 12 * Math.floor(i / intervals.length) + intervals[i % intervals.length]; }).map(x => clamp(x, 21, 108));
}
export function emptySteps() { return Array.from({ length: 8 }, () => Array(16).fill(0)); }
export function pattern(id) {
    const s = emptySteps();
    const put = (row, indices, v = 0.8) => indices.forEach(i => s[row][i] = v);
    if (id === 'house') {
        put(0, [0, 4, 8, 12]);
        put(2, [4, 12], .6);
        put(3, [2, 6, 10, 14], .5);
        put(4, [14], .4);
    }
    if (id === 'lofi') {
        put(0, [0, 7, 10], .75);
        put(1, [4, 12], .65);
        put(3, [0, 2, 4, 6, 8, 10, 12, 14], .3);
        put(7, [3, 11], .25);
    }
    if (id === 'break') {
        put(0, [0, 6, 10], .9);
        put(1, [4, 12], .75);
        put(1, [7, 15], .25);
        put(3, [0, 2, 3, 6, 8, 10, 11, 14], .42);
        put(4, [13], .45);
    }
    if (id === 'pop') {
        put(0, [0, 8], .8);
        put(1, [4, 12], .65);
        put(3, [0, 2, 4, 6, 8, 10, 12, 14], .4);
        put(2, [12], .35);
    }
    return s;
}
export function initialSession() { return { version: 1, name: '我的演奏', bpm: 96, bars: 2, swing: 0, master: .7, reverb: .2, delay: 0, tone: .7, velocity: .75, octave: 4, root: 0, scale: 'chromatic', chord: false, instrument: 'piano', metronome: false, quantize: true, drumEnabled: false, drumGain: .8, steps: pattern('lofi'), events: [], clips: clipNames.map(name => ({ name, gain: .8, rate: 1, loop: false, start: 0, end: 1 })) }; }
export function quantizedBeat(beat, bars, quantize) { return wrap(quantize ? Math.round(beat * 4) / 4 : beat, bars * 4); }
export function swingBeat(step, swing) { return step / 4 + (step % 2 ? swing * .125 : 0); }
export function validateSession(raw) {
    if (!raw || typeof raw !== 'object')
        throw Error('无法识别这个演奏文件');
    const x = raw;
    if (x.version !== 1)
        throw Error('不支持这个演奏文件版本');
    const d = initialSession();
    const out = { ...d };
    const num = (k, min, max) => { const n = x[k]; if (typeof n !== 'number' || !Number.isFinite(n) || n < min || n > max)
        throw Error('演奏文件参数无效：' + k); return n; };
    if (x.projectId !== undefined) {
        if (typeof x.projectId !== 'string' || !/^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|legacy-[0-9a-f]{24})$/.test(x.projectId))
            throw Error('作品编号无效');
        out.projectId = x.projectId;
    }
    if (typeof x.sourcePreset === 'string')
        out.sourcePreset = x.sourcePreset.slice(0, 64);
    out.name = typeof x.name === 'string' ? x.name.slice(0, 80) : d.name;
    for (const [key, min, max] of [['bpm', 40, 200], ['bars', 1, 8], ['swing', 0, 1], ['master', 0, 1], ['reverb', 0, 1], ['delay', 0, 1], ['tone', 0, 1], ['velocity', .05, 1], ['octave', 1, 6], ['root', 0, 11], ['drumGain', 0, 1]])
        out[key] = num(key, min, max);
    if (![1, 2, 4, 8].includes(out.bars) || !Number.isInteger(out.octave) || !Number.isInteger(out.root))
        throw Error('演奏文件音域无效');
    if (!Object.hasOwn(scales, String(x.scale)))
        throw Error('演奏文件音阶无效');
    out.scale = x.scale;
    if (!instruments.some(i => i[0] === x.instrument))
        throw Error('演奏文件音色无效');
    out.instrument = x.instrument;
    for (const k of ['chord', 'metronome', 'quantize', 'drumEnabled']) {
        if (typeof x[k] !== 'boolean')
            throw Error('演奏文件开关无效');
        out[k] = x[k];
    }
    if (!Array.isArray(x.steps) || x.steps.length !== 8)
        throw Error('鼓机轨道无效');
    out.steps = x.steps.map(row => { if (!Array.isArray(row) || row.length !== 16 || row.some(n => typeof n !== 'number' || !Number.isFinite(n) || n < 0 || n > 1))
        throw Error('鼓机节奏无效'); return [...row]; });
    if (!Array.isArray(x.events) || x.events.length > 4096)
        throw Error('录制事件过多');
    out.events = x.events.map(e => { if (!e || !['note', 'drum', 'clip'].includes(e.kind) || !Number.isFinite(e.beat) || e.beat < 0 || e.beat >= out.bars * 4 || !Number.isFinite(e.duration) || e.duration <= 0 || e.duration > out.bars * 4 || !Number.isInteger(e.value) || e.value < (e.kind === 'note' ? 21 : 0) || e.value > (e.kind === 'note' ? 108 : 7) || !Number.isFinite(e.velocity) || e.velocity < .05 || e.velocity > 1 || !instruments.some(i => i[0] === e.instrument))
        throw Error('录制事件无效'); return { id: String(e.id).slice(0, 80), kind: e.kind, beat: e.beat, duration: e.duration, value: e.value, velocity: e.velocity, instrument: e.instrument }; });
    if (!Array.isArray(x.clips) || x.clips.length !== 8)
        throw Error('片段数量无效');
    let total = 0;
    out.clips = x.clips.map(c => {
        if (!c || typeof c.name !== 'string' || typeof c.loop !== 'boolean' || !Number.isFinite(c.gain) || c.gain < 0 || c.gain > 1 || !Number.isFinite(c.rate) || c.rate < .5 || c.rate > 2 || !Number.isFinite(c.start) || !Number.isFinite(c.end) || c.start < 0 || c.end > 1 || c.end - c.start < .01)
            throw Error('片段参数无效');
        if (c.audio !== undefined && (typeof c.audio !== 'string' || c.audio.length > 12 * 1024 * 1024 || !/^data:audio\/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=]+$/.test(c.audio)))
            throw Error('片段音频无效');
        total += c.audio?.length ?? 0;
        if (c.preset !== undefined && (typeof c.preset !== 'string' || !/^[a-z0-9-]{1,64}$/.test(c.preset)))
            throw Error('片段预设无效');
        return { ...(c.preset ? { preset: c.preset } : {}), name: c.name.slice(0, 80), gain: c.gain, rate: c.rate, loop: c.loop, start: c.start, end: c.end, ...(c.audio ? { audio: c.audio } : {}) };
    });
    if (total > 44 * 1024 * 1024)
        throw Error('导入音频总量超过 32 MB');
    return out;
}
// Original patterns written for this experiment, independent of commercial recordings.
export function clipScore(slot) {
    const events = [];
    const add = (kind, value, beat, duration, velocity, instrument = 'piano') => events.push({ kind, value, beat, duration, velocity, instrument });
    if (slot < 4) {
        const melodies = [[60, 64, 67, 71, 69, 67, 64, 62], [57, 60, 64, 67], [72, 79, 76, 74, 71, 76, 72, 67], [60, 67, 72, 76, 74, 71, 67, 64]];
        melodies[slot].forEach((n, i) => add('note', n, i * (slot === 1 ? 1 : .5), slot === 1 ? 1.6 : .48, .55, ['piano', 'warm', 'electric', 'pluck'][slot]));
    }
    if (slot === 4)
        [36, 36, 43, 46, 41, 39, 43, 38].forEach((n, i) => add('note', n, i * .5, .35, .65, 'pluck'));
    if (slot === 5 || slot === 6)
        pattern(slot === 5 ? 'house' : 'lofi').forEach((r, d) => r.forEach((v, i) => { if (v)
            add('drum', d, i / 4, .15, v); }));
    if (slot === 7)
        [84, 79, 76, 72, 79, 83, 88, 86].forEach((n, i) => add('note', n, i * .5, .8, .4, 'electric'));
    return { beats: 4, events };
}
export function demoEvents() { return [...clipScore(0).events, ...clipScore(1).events.map(e => ({ ...e, beat: e.beat + 4 }))].map((e, i) => ({ ...e, id: 'demo-' + i })); }
export function encodeWav(channels, sampleRate) {
    const frames = channels[0].length, count = channels.length;
    const b = new ArrayBuffer(44 + frames * count * 2), v = new DataView(b);
    const str = (o, s) => [...s].forEach((c, i) => v.setUint8(o + i, c.charCodeAt(0)));
    str(0, 'RIFF');
    v.setUint32(4, b.byteLength - 8, true);
    str(8, 'WAVE');
    str(12, 'fmt ');
    v.setUint32(16, 16, true);
    v.setUint16(20, 1, true);
    v.setUint16(22, count, true);
    v.setUint32(24, sampleRate, true);
    v.setUint32(28, sampleRate * count * 2, true);
    v.setUint16(32, count * 2, true);
    v.setUint16(34, 16, true);
    str(36, 'data');
    v.setUint32(40, frames * count * 2, true);
    for (let i = 0; i < frames; i++)
        for (let c = 0; c < count; c++) {
            const n = clamp(channels[c][i], -1, 1);
            v.setInt16(44 + (i * count + c) * 2, n < 0 ? n * 32768 : n * 32767, true);
        }
    return b;
}
