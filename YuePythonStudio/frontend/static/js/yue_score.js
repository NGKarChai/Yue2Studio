// YuE Sheet Music & Symbolic Score Component
class YueScoreViewer {
    constructor() {
        this.canvas = document.getElementById('yue_score_canvas');
        this.ctx = this.canvas ? this.canvas.getContext('2d') : null;
        this.abcEditor = document.getElementById('yue_abc_editor_textarea');
        this.btnUpdateScore = document.getElementById('yue_btn_update_score');

        this.btnExportMidi = document.getElementById('yue_btn_export_midi');
        this.btnExportMusicXml = document.getElementById('yue_btn_export_musicxml');
        this.btnExportAbc = document.getElementById('yue_btn_export_abc');

        this.currentParsed = null;
        this.init();
    }

    init() {
        if (this.btnUpdateScore && this.abcEditor) {
            this.btnUpdateScore.addEventListener('click', () => {
                this.renderFromAbc(this.abcEditor.value);
            });
        }

        if (this.btnExportMidi) {
            this.btnExportMidi.addEventListener('click', () => this.exportFile('/api/export/midi', 'composition.mid'));
        }

        if (this.btnExportMusicXml) {
            this.btnExportMusicXml.addEventListener('click', () => this.exportFile('/api/export/musicxml', 'composition.musicxml'));
        }

        if (this.btnExportAbc) {
            this.btnExportAbc.addEventListener('click', () => {
                const text = this.abcEditor ? this.abcEditor.value : '';
                const blob = new Blob([text], { type: 'text/plain' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = 'composition.abc';
                a.click();
                URL.revokeObjectURL(url);
            });
        }

        this.resizeCanvas();
        window.addEventListener('resize', () => this.resizeCanvas());
    }

    resizeCanvas() {
        if (!this.canvas) return;
        const rect = this.canvas.getBoundingClientRect();
        this.canvas.width = rect.width * window.devicePixelRatio;
        this.canvas.height = (rect.height || 180) * window.devicePixelRatio;
        if (this.ctx) {
            this.ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
        }
        this.draw();
    }

    renderFromAbc(abcText) {
        if (this.abcEditor) {
            this.abcEditor.value = abcText;
        }

        // Basic client-side parse of ABC for visual rendering
        const lines = abcText.split('\n');
        let key = 'C';
        let tempo = '120';
        let meter = '4/4';
        const measures = [];
        let currentChord = '';
        let currentNotes = [];

        lines.forEach(line => {
            const trimmed = line.trim();
            if (trimmed.startsWith('K:')) key = trimmed.substring(2).trim();
            if (trimmed.startsWith('Q:')) tempo = trimmed.substring(2).trim();
            if (trimmed.startsWith('M:')) meter = trimmed.substring(2).trim();

            if (!trimmed.startsWith('%') && !trimmed.includes(':')) {
                // Parse measures separated by |
                const parts = trimmed.split('|');
                parts.forEach(part => {
                    const seg = part.trim();
                    if (!seg) return;
                    // Look for chord e.g. "C"
                    const chordMatch = seg.match(/"([^"]+)"/);
                    const chord = chordMatch ? chordMatch[1] : '';
                    // Extract note letters
                    const notes = seg.replace(/"[^"]+"/g, '').match(/[A-Ga-g][0-9]*/g) || ['C', 'E', 'G'];
                    measures.push({ chord, notes });
                });
            }
        });

        this.currentParsed = { key, tempo, meter, measures: measures.slice(0, 8) };
        this.draw();
    }

    draw() {
        if (!this.ctx || !this.canvas) return;
        const width = this.canvas.width / window.devicePixelRatio;
        const height = this.canvas.height / window.devicePixelRatio;

        this.ctx.clearRect(0, 0, width, height);

        if (!this.currentParsed || !this.currentParsed.measures.length) {
            this.ctx.fillStyle = '#94a3b8';
            this.ctx.font = '13px sans-serif';
            this.ctx.fillText('No active score. Generate music or input ABC to visualize.', 20, height / 2);
            return;
        }

        // Draw musical staff (5 lines)
        const startY = 60;
        const lineGap = 12;
        this.ctx.strokeStyle = '#2b3042';
        this.ctx.lineWidth = 1.5;

        for (let i = 0; i < 5; i++) {
            const y = startY + i * lineGap;
            this.ctx.beginPath();
            this.ctx.moveTo(20, y);
            this.ctx.lineTo(width - 20, y);
            this.ctx.stroke();
        }

        // Draw Clef & Key
        this.ctx.fillStyle = '#06b6d4';
        this.ctx.font = 'bold 24px serif';
        this.ctx.fillText('𝄞', 26, startY + 36);

        this.ctx.fillStyle = '#94a3b8';
        this.ctx.font = 'bold 12px sans-serif';
        this.ctx.fillText(`Key: ${this.currentParsed.key}`, 60, 30);
        this.ctx.fillText(`Meter: ${this.currentParsed.meter}`, 140, 30);
        this.ctx.fillText(`BPM: ${this.currentParsed.tempo}`, 230, 30);

        // Draw measures and notes
        const measureStartX = 70;
        const availableWidth = width - measureStartX - 30;
        const measureWidth = availableWidth / this.currentParsed.measures.length;

        this.currentParsed.measures.forEach((measure, idx) => {
            const mX = measureStartX + idx * measureWidth;

            // Bar line
            this.ctx.strokeStyle = '#3b4256';
            this.ctx.beginPath();
            this.ctx.moveTo(mX + measureWidth, startY);
            this.ctx.lineTo(mX + measureWidth, startY + 4 * lineGap);
            this.ctx.stroke();

            // Chord label
            if (measure.chord) {
                this.ctx.fillStyle = '#f59e0b';
                this.ctx.font = 'bold 13px monospace';
                this.ctx.fillText(measure.chord, mX + 10, startY - 14);
            }

            // Draw note heads
            const noteStep = (measureWidth - 20) / Math.max(1, measure.notes.length);
            measure.notes.forEach((noteSym, nIdx) => {
                const nX = mX + 12 + nIdx * noteStep;
                const char = noteSym[0].toUpperCase();
                // Map pitch step to staff line
                const pitchOffsets = { 'C': 4, 'D': 3.5, 'E': 3, 'F': 2.5, 'G': 2, 'A': 1.5, 'B': 1 };
                const offset = pitchOffsets[char] !== undefined ? pitchOffsets[char] : 2;
                const nY = startY + offset * lineGap;

                // Oval note head
                this.ctx.fillStyle = '#6366f1';
                this.ctx.beginPath();
                this.ctx.ellipse(nX, nY, 6, 4.5, -0.2, 0, Math.PI * 2);
                this.ctx.fill();

                // Stem
                this.ctx.strokeStyle = '#6366f1';
                this.ctx.lineWidth = 1.5;
                this.ctx.beginPath();
                this.ctx.moveTo(nX + 5, nY);
                this.ctx.lineTo(nX + 5, nY - 26);
                this.ctx.stroke();
            });
        });
    }

    exportFile(endpoint, filename) {
        const text = this.abcEditor ? this.abcEditor.value : '';
        const formData = new FormData();
        formData.append('abc_text', text);

        fetch(endpoint, {
            method: 'POST',
            body: formData
        })
        .then(res => res.blob())
        .then(blob => {
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            a.click();
            URL.revokeObjectURL(url);
        })
        .catch(err => alert('Export failed: ' + err));
    }
}
