// Audio: channel 0 streams Ogg Vorbis BGM (tremor) from a worker thread; channels 1..15
// play preloaded PCM16 sound effects round-robin.
#include "engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tremor/ivorbisfile.h>

#define BGM_CH 0
#define SE_FIRST 1
#define SE_LAST 15
#define BGM_BUFS 4
#define BGM_SAMPLES 4096
#define MAX_SE 128

static bool ndspOk;
static Thread bgmThread;
static LightLock bgmLock;
static volatile bool bgmRun, bgmQuit;
static OggVorbis_File vf;
static bool vfOpen, bgmLoop;
static ndspWaveBuf bgmBufs[BGM_BUFS];
static s16 *bgmData;
static float bgmVol = 1.0f;
static double bgmPos;
static int bgmRate;

typedef struct {
    s16 *data;
    u32 samples;
    u32 rate;
    bool used;
} Se;
static Se ses[MAX_SE];
static ndspWaveBuf seBufs[SE_LAST + 1];
static int seNext = SE_FIRST;

static void set_mix(int ch, float vol) {
    float mix[12] = {0};
    mix[0] = mix[1] = vol;
    ndspChnSetMix(ch, mix);
}

// fills one wave buffer; returns false at end of stream (when not looping)
static bool bgm_fill(ndspWaveBuf *wb) {
    char *dst = (char *)wb->data_pcm16;
    int want = BGM_SAMPLES * 4, got = 0;
    while (got < want) {
        int bs;
        long r = ov_read(&vf, dst + got, want - got, &bs);
        if (r <= 0) {
            if (r == 0 && bgmLoop) { ov_pcm_seek(&vf, 0); continue; }
            break;
        }
        got += r;
    }
    if (got == 0) return false;
    wb->nsamples = got / 4;
    DSP_FlushDataCache(wb->data_pcm16, got);
    ndspChnWaveBufAdd(BGM_CH, wb);
    return true;
}

static void bgm_worker(void *arg) {
    (void)arg;
    while (!bgmQuit) {
        LightLock_Lock(&bgmLock);
        if (bgmRun && vfOpen) {
            for (int i = 0; i < BGM_BUFS; i++) {
                if (bgmBufs[i].status == NDSP_WBUF_DONE || bgmBufs[i].status == NDSP_WBUF_FREE) {
                    if (!bgm_fill(&bgmBufs[i])) { bgmRun = false; break; }
                }
            }
            if (vfOpen) bgmPos = (double)ov_pcm_tell(&vf) / bgmRate;
        }
        LightLock_Unlock(&bgmLock);
        svcSleepThread(10 * 1000000LL);
    }
}

bool audio_init(void) {
    ndspOk = R_SUCCEEDED(ndspInit());
    if (!ndspOk) return false;  // needs sdmc:/3ds/dspfirm.cdc (DSP1)
    ndspSetOutputMode(NDSP_OUTPUT_STEREO);
    LightLock_Init(&bgmLock);
    bgmData = linearAlloc(BGM_BUFS * BGM_SAMPLES * 4);
    memset(bgmBufs, 0, sizeof(bgmBufs));
    for (int i = 0; i < BGM_BUFS; i++) {
        bgmBufs[i].data_pcm16 = bgmData + i * BGM_SAMPLES * 2;
        bgmBufs[i].status = NDSP_WBUF_FREE;
    }
    for (int ch = SE_FIRST; ch <= SE_LAST; ch++) {
        ndspChnSetInterp(ch, NDSP_INTERP_LINEAR);
        ndspChnSetFormat(ch, NDSP_FORMAT_MONO_PCM16);
    }
    s32 prio;
    svcGetThreadPriority(&prio, CUR_THREAD_HANDLE);
    bgmThread = threadCreate(bgm_worker, NULL, 32 * 1024, prio - 1, -2, false);
    return true;
}

bool audio_ok(void) { return ndspOk; }

void audio_exit(void) {
    if (!ndspOk) return;
    bgmQuit = true;
    threadJoin(bgmThread, U64_MAX);
    threadFree(bgmThread);
    audio_bgm_stop();
    for (int i = 0; i < MAX_SE; i++) audio_se_free(i);
    linearFree(bgmData);
    ndspExit();
}

bool audio_bgm_play(const char *path, bool loop) {
    if (!ndspOk) return false;
    audio_bgm_stop();
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    LightLock_Lock(&bgmLock);
    if (ov_open(f, &vf, NULL, 0) < 0) {
        fclose(f);
        LightLock_Unlock(&bgmLock);
        return false;
    }
    vorbis_info *vi = ov_info(&vf, -1);
    bgmRate = vi->rate;
    ndspChnReset(BGM_CH);
    ndspChnSetInterp(BGM_CH, NDSP_INTERP_POLYPHASE);
    ndspChnSetRate(BGM_CH, vi->rate);
    ndspChnSetFormat(BGM_CH, vi->channels == 2 ? NDSP_FORMAT_STEREO_PCM16 : NDSP_FORMAT_MONO_PCM16);
    set_mix(BGM_CH, bgmVol);
    for (int i = 0; i < BGM_BUFS; i++) bgmBufs[i].status = NDSP_WBUF_FREE;
    vfOpen = true;
    bgmLoop = loop;
    bgmPos = 0;
    bgmRun = true;
    LightLock_Unlock(&bgmLock);
    return true;
}

void audio_bgm_stop(void) {
    if (!ndspOk) return;
    LightLock_Lock(&bgmLock);
    bgmRun = false;
    ndspChnWaveBufClear(BGM_CH);
    if (vfOpen) {
        ov_clear(&vf);  // closes the FILE*
        vfOpen = false;
    }
    LightLock_Unlock(&bgmLock);
}

void audio_bgm_volume(float v) {
    bgmVol = v;
    if (ndspOk) set_mix(BGM_CH, v);
}

double audio_bgm_position(void) { return bgmPos; }

int audio_se_load(const char *path) {
    if (!ndspOk) return -1;
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    u8 hdr[16];
    if (fread(hdr, 1, 16, f) != 16 || memcmp(hdr, "PCM1", 4) != 0) {
        fclose(f);
        return -1;
    }
    u32 rate = hdr[4] | (hdr[5] << 8) | (hdr[6] << 16) | ((u32)hdr[7] << 24);
    u32 n = hdr[12] | (hdr[13] << 8) | (hdr[14] << 16) | ((u32)hdr[15] << 24);
    int id = -1;
    for (int i = 0; i < MAX_SE; i++)
        if (!ses[i].used) { id = i; break; }
    if (id < 0) { fclose(f); return -1; }
    ses[id].data = linearAlloc(n * 2);
    if (!ses[id].data || fread(ses[id].data, 2, n, f) != n) {
        if (ses[id].data) linearFree(ses[id].data);
        fclose(f);
        return -1;
    }
    fclose(f);
    DSP_FlushDataCache(ses[id].data, n * 2);
    ses[id].samples = n;
    ses[id].rate = rate;
    ses[id].used = true;
    return id;
}

void audio_se_free(int id) {
    if (id < 0 || id >= MAX_SE || !ses[id].used) return;
    for (int ch = SE_FIRST; ch <= SE_LAST; ch++)
        if (seBufs[ch].data_pcm16 == ses[id].data) ndspChnWaveBufClear(ch);
    linearFree(ses[id].data);
    ses[id].used = false;
}

void audio_se_free_all(void) {
    for (int i = 0; i < MAX_SE; i++) audio_se_free(i);
}

void audio_se_play(int id, float volume) {
    if (!ndspOk || id < 0 || id >= MAX_SE || !ses[id].used) return;
    int ch = seNext;
    seNext = seNext >= SE_LAST ? SE_FIRST : seNext + 1;
    ndspChnWaveBufClear(ch);
    ndspChnSetRate(ch, ses[id].rate);
    set_mix(ch, volume);
    memset(&seBufs[ch], 0, sizeof(ndspWaveBuf));
    seBufs[ch].data_pcm16 = ses[id].data;
    seBufs[ch].nsamples = ses[id].samples;
    ndspChnWaveBufAdd(ch, &seBufs[ch]);
}
