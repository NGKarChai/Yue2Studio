// YuE Cover Studio & Reference Audio Analysis Component
class YueCoverStudio {
    constructor(scoreViewer) {
        this.scoreViewer = scoreViewer;
        this.fileInput = document.getElementById('yue_cover_file_input');
        this.uploadBox = document.getElementById('yue_cover_upload_box');
        this.keyBadge = document.getElementById('yue_cover_key_badge');
        this.bpmBadge = document.getElementById('yue_cover_bpm_badge');
        this.canvas = document.getElementById('yue_pitch_canvas');
        this.ctx = this.canvas ? this.canvas.getContext('2d') : null;

        this.transSlider = document.getElementById('yue_transposition_slider');
        this.transVal = document.getElementById('yue_transposition_val');
        this.btnTransDown = document.getElementById('yue_btn_transpose_down');
        this.btnTransUp = document.getElementById('yue_btn_transpose_up');

        this.btnModeMajor = document.getElementById('yue_btn_mode_major');
        this.btnModeMinor = document.getElementById('yue_btn_mode_minor');

        this.btnExtractToScore = document.getElementById('yue_btn_extract_melody_to_score');
        this.btnAlignLyrics = document.getElementById('yue_btn_align_lyrics');

        this.currentAnalysis = null;
        this.init();
    }

    init() {
        if (this.uploadBox && this.fileInput) {
            this.uploadBox.addEventListener('click', () => this.fileInput.click());
            this.fileInput.addEventListener('change', (e) => {
                if (e.target.files && e.target.files[0]) {
                    this.uploadAudio(e.target.files[0]);
                }
            });
        }

        if (this.transSlider && this.transVal) {
            this.transSlider.addEventListener('input', (e) => {
                const val = e.target.value;
                this.transVal.textContent = (val > 0 ? '+' : '') + val;
            });
            this.transSlider.addEventListener('change', (e) => {
                this.transposeAbc(parseInt(e.target.value));
            });
        }

        if (this.btnTransDown && this.transSlider) {
            this.btnTransDown.addEventListener('click', () => {
                this.transSlider.value = Math.max(-12, parseInt(this.transSlider.value) - 1);
                this.transSlider.dispatchEvent(new Event('input'));
                this.transSlider.dispatchEvent(new Event('change'));
            });
        }

        if (this.btnTransUp && this.transSlider) {
            this.btnTransUp.addEventListener('click', () => {
                this.transSlider.value = Math.min(12, parseInt(this.transSlider.value) + 1);
                this.transSlider.dispatchEvent(new Event('input'));
                this.transSlider.dispatchEvent(new Event('change'));
            });
        }

        if (this.btnModeMajor) {
            this.btnModeMajor.addEventListener('click', () => this.modulateMode('major'));
        }

        if (this.btnModeMinor) {
            this.btnModeMinor.addEventListener('click', () => this.modulateMode('minor'));
        }

        if (this.btnExtractToScore) {
            this.btnExtractToScore.addEventListener('click', () => {
                if (this.currentAnalysis && this.currentAnalysis.abc_score) {
                    this.scoreViewer.renderFromAbc(this.currentAnalysis.abc_score);
                    alert('Melody transcribed to Symbolic Score tab!');
                }
            });
        }

        if (this.btnAlignLyrics) {
            this.btnAlignLyrics.addEventListener('click', () => {
                const lyricsEl = document.getElementById('yue_lyrics_textarea');
                const lyricsText = lyricsEl ? lyricsEl.value : '';
                if (!this.currentAnalysis || !this.currentAnalysis.abc_score) {
                    alert('Please upload a reference audio track first.');
                    return;
                }
                const aligned = this.realignClientLyrics(this.currentAnalysis.abc_score, lyricsText);
                this.scoreViewer.renderFromAbc(aligned);
                alert('Lyrics syllabically aligned to reference melody!');
            });
        }

        this.resizeCanvas();
        window.addEventListener('resize', () => this.resizeCanvas());
    }

    resizeCanvas() {
        if (!this.canvas) return;
        const rect = this.canvas.getBoundingClientRect();
        this.canvas.width = rect.width * window.devicePixelRatio;
        this.canvas.height = (rect.height || 120) * window.devicePixelRatio;
        if (this.ctx) {
            this.ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
        }
        this.drawPitchContour();
    }

    uploadAudio(file) {
        const formData = new FormData();
        formData.append('file', file);

        if (this.uploadBox) {
            this.uploadBox.innerHTML = '<span>⏳ Analyzing audio (F0 tracking & key estimation)...</span>';
        }

        fetch('/api/reference/analyze', {
            method: 'POST',
            body: formData
        })
        .then(res => {
            if (!res.ok) throw new Error('Analysis failed');
            return res.json();
        })
        .then(data => {
            this.currentAnalysis = data;
            if (this.uploadBox) {
                this.uploadBox.innerHTML = `<span>🎵 ${file.name} (${data.duration_seconds.toFixed(1)}s)</span>`;
            }
            if (this.keyBadge) {
                this.keyBadge.textContent = `${data.estimated_key} ${data.estimated_mode} (${Math.round(data.confidence * 100)}%)`;
            }
            if (this.bpmBadge) {
                this.bpmBadge.textContent = `${data.estimated_bpm} BPM`;
            }
            this.drawPitchContour();
        })
        .catch(err => {
            alert('Audio analysis error: ' + err.message);
            if (this.uploadBox) {
                this.uploadBox.innerHTML = '<span>Drop reference audio here (.wav, .mp3, .flac) or click to upload</span>';
            }
        });
    }

    drawPitchContour() {
        if (!this.ctx || !this.canvas) return;
        const width = this.canvas.width / window.devicePixelRatio;
        const height = this.canvas.height / window.devicePixelRatio;

        this.ctx.clearRect(0, 0, width, height);

        if (!this.currentAnalysis || !this.currentAnalysis.pitch_contour || !this.currentAnalysis.pitch_contour.length) {
            this.ctx.fillStyle = '#94a3b8';
            this.ctx.font = '12px sans-serif';
            this.ctx.fillText('Pitch trajectory (F0) will render after uploading reference audio.', 20, height / 2);
            return;
        }

        const pts = this.currentAnalysis.pitch_contour;
        const maxPitch = 800; // Hz
        const minPitch = 60;  // Hz

        this.ctx.strokeStyle = '#06b6d4';
        this.ctx.lineWidth = 2;
        this.ctx.beginPath();

        let inSegment = false;
        pts.forEach((hz, idx) => {
            const x = (idx / pts.length) * width;
            if (hz > minPitch) {
                const norm = Math.max(0, Math.min(1, (hz - minPitch) / (maxPitch - minPitch)));
                const y = height - norm * (height - 16) - 8;
                if (!inSegment) {
                    this.ctx.moveTo(x, y);
                    inSegment = true;
                } else {
                    this.ctx.lineTo(x, y);
                }
            } else {
                inSegment = false;
            }
        });
        this.ctx.stroke();
    }

    transposeAbc(semitones) {
        const text = this.scoreViewer.abcEditor ? this.scoreViewer.abcEditor.value : '';
        if (!text) return;

        fetch('/api/symbolic/transpose', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ abc_text: text, semitones: semitones })
        })
        .then(res => res.json())
        .then(data => {
            this.scoreViewer.renderFromAbc(data.transposed_abc);
        })
        .catch(err => console.error('Transpose error:', err));
    }

    modulateMode(mode) {
        const text = this.scoreViewer.abcEditor ? this.scoreViewer.abcEditor.value : '';
        if (!text) return;

        fetch('/api/symbolic/modulate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ abc_text: text, target_mode: mode })
        })
        .then(res => res.json())
        .then(data => {
            this.scoreViewer.renderFromAbc(data.modulated_abc);
        })
        .catch(err => console.error('Modulate error:', err));
    }

    realignClientLyrics(abcText, lyrics) {
        const words = lyrics.replace(/\[\w+\]/g, '').trim().split(/\s+/);
        const lines = abcText.split('\n').filter(l => !l.startsWith('w:') && !l.startsWith('W:'));
        let wordIdx = 0;
        const out = [];

        lines.forEach(line => {
            out.push(line);
            if (!line.startsWith('%') && !line.includes(':') && line.trim()) {
                if (wordIdx < words.length) {
                    const chunk = words.slice(wordIdx, wordIdx + 6).join(' ');
                    out.push(`w: ${chunk}`);
                    wordIdx += 6;
                }
            }
        });
        return out.join('\n');
    }
}
