// YuE Waveform Player Component
class YueWaveformPlayer {
    constructor() {
        this.audioElement = new Audio();
        this.canvas = document.getElementById('yue_waveform_canvas');
        this.ctx = this.canvas ? this.canvas.getContext('2d') : null;
        this.playBtn = document.getElementById('yue_btn_play_pause');
        this.timeDisplay = document.getElementById('yue_time_display');
        this.volumeSlider = document.getElementById('yue_volume_slider');
        this.downloadBtn = document.getElementById('yue_btn_download_wav');

        this.isPlaying = false;
        this.duration = 0;
        this.currentTime = 0;
        this.peaks = [];
        this.currentUrl = null;

        this.init();
    }

    init() {
        if (!this.canvas) return;

        this.resizeCanvas();
        window.addEventListener('resize', () => this.resizeCanvas());

        this.audioElement.addEventListener('timeupdate', () => {
            this.currentTime = this.audioElement.currentTime;
            this.updateTimeDisplay();
            this.draw();
        });

        this.audioElement.addEventListener('ended', () => {
            this.isPlaying = false;
            this.updatePlayBtn();
            this.draw();
        });

        this.audioElement.addEventListener('loadedmetadata', () => {
            this.duration = this.audioElement.duration;
            this.updateTimeDisplay();
            this.generateMockPeaks();
            this.draw();
        });

        if (this.playBtn) {
            this.playBtn.addEventListener('click', () => this.togglePlay());
        }

        if (this.volumeSlider) {
            this.volumeSlider.addEventListener('input', (e) => {
                this.audioElement.volume = parseFloat(e.target.value);
            });
        }

        this.canvas.addEventListener('click', (e) => {
            const rect = this.canvas.getBoundingClientRect();
            const clickX = e.clientX - rect.left;
            const frac = Math.max(0, Math.min(1, clickX / rect.width));
            if (this.duration > 0) {
                this.audioElement.currentTime = frac * this.duration;
            }
        });
    }

    resizeCanvas() {
        if (!this.canvas) return;
        const rect = this.canvas.getBoundingClientRect();
        this.canvas.width = rect.width * window.devicePixelRatio;
        this.canvas.height = rect.height * window.devicePixelRatio;
        if (this.ctx) {
            this.ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
        }
        this.draw();
    }

    loadAudio(url) {
        this.currentUrl = url;
        this.audioElement.src = url;
        this.audioElement.load();
        if (this.downloadBtn) {
            this.downloadBtn.href = url;
            this.downloadBtn.style.display = 'inline-flex';
        }
    }

    togglePlay() {
        if (!this.currentUrl) return;
        if (this.isPlaying) {
            this.audioElement.pause();
            this.isPlaying = false;
        } else {
            this.audioElement.play();
            this.isPlaying = true;
        }
        this.updatePlayBtn();
    }

    updatePlayBtn() {
        if (!this.playBtn) return;
        this.playBtn.innerHTML = this.isPlaying ? '⏸ Pause' : '▶ Play';
    }

    updateTimeDisplay() {
        if (!this.timeDisplay) return;
        const cur = this.formatTime(this.currentTime);
        const dur = this.formatTime(this.duration);
        this.timeDisplay.textContent = `${cur} / ${dur}`;
    }

    formatTime(sec) {
        if (isNaN(sec) || sec <= 0) return '0:00';
        const m = Math.floor(sec / 60);
        const s = Math.floor(sec % 60);
        return `${m}:${s < 10 ? '0' : ''}${s}`;
    }

    generateMockPeaks() {
        const numBars = 120;
        this.peaks = [];
        for (let i = 0; i < numBars; i++) {
            const val = 0.2 + 0.7 * Math.sin(i * 0.1) * Math.sin(i * 0.2) + Math.random() * 0.2;
            this.peaks.push(Math.min(1.0, Math.max(0.1, val)));
        }
    }

    draw() {
        if (!this.ctx || !this.canvas) return;
        const width = this.canvas.width / window.devicePixelRatio;
        const height = this.canvas.height / window.devicePixelRatio;

        this.ctx.clearRect(0, 0, width, height);

        if (this.peaks.length === 0) {
            this.ctx.fillStyle = '#2b3042';
            this.ctx.fillRect(0, height / 2 - 1, width, 2);
            return;
        }

        const barWidth = width / this.peaks.length;
        const progressFrac = this.duration > 0 ? this.currentTime / this.duration : 0;
        const currentBar = Math.floor(progressFrac * this.peaks.length);

        for (let i = 0; i < this.peaks.length; i++) {
            const barH = this.peaks[i] * (height - 8);
            const x = i * barWidth;
            const y = (height - barH) / 2;

            if (i <= currentBar) {
                this.ctx.fillStyle = '#6366f1';
            } else {
                this.ctx.fillStyle = '#2b3042';
            }

            this.ctx.fillRect(x + 1, y, Math.max(1, barWidth - 2), barH);
        }

        // Draw Scrubber Playhead
        const playheadX = progressFrac * width;
        this.ctx.fillStyle = '#06b6d4';
        this.ctx.fillRect(playheadX - 1, 0, 2, height);
    }
}
