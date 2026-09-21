// Global helper functions for interactive duration control
window.yue_updateDurationDisplay = function(sec) {
    sec = parseInt(sec, 10);
    if (isNaN(sec)) sec = 60;
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    const sFormatted = s < 10 ? '0' + s : s;
    const label = `${sec}s (${m}m ${sFormatted}s)`;
    const elVal = document.getElementById('yue_param_seconds_val');
    const elHint = document.getElementById('yue_param_tokens_hint');
    if (elVal) elVal.textContent = label;
    if (elHint) elHint.textContent = `(~${(sec * 100).toLocaleString()} tokens)`;
};

window.yue_setDuration = function(sec) {
    const slider = document.getElementById('yue_param_seconds');
    if (slider) {
        slider.value = sec;
    }
    window.yue_updateDurationDisplay(sec);
};

// YuE Python Studio Main Application Controller
document.addEventListener('DOMContentLoaded', () => {
    // Initialize duration display immediately
    const initSlider = document.getElementById('yue_param_seconds');
    if (initSlider) {
        window.yue_updateDurationDisplay(initSlider.value);
    }

    // 1. Initialize Components
    const waveformPlayer = new YueWaveformPlayer();
    const scoreViewer = new YueScoreViewer();
    const coverStudio = new YueCoverStudio(scoreViewer);

    // 2. Tab Navigation
    const navItems = document.querySelectorAll('.yue_nav_item');
    const tabPanes = document.querySelectorAll('.yue_tab_pane');

    navItems.forEach(item => {
        item.addEventListener('click', () => {
            const targetId = item.getAttribute('data-tab');

            navItems.forEach(n => n.classList.remove('yue_active'));
            tabPanes.forEach(p => p.classList.remove('yue_active'));

            item.classList.add('yue_active');
            const targetPane = document.getElementById(targetId);
            if (targetPane) {
                targetPane.classList.add('yue_active');
            }

            if (targetId === 'yue_tab_score') {
                scoreViewer.resizeCanvas();
            } else if (targetId === 'yue_tab_cover') {
                coverStudio.resizeCanvas();
            } else if (targetId === 'yue_tab_library') {
                loadHistory();
            }
        });
    });

    // 3. Load System Status and Update Footer (Rules 7, 8)
    function loadSystemStatus() {
        fetch('/api/system/status')
            .then(res => res.json())
            .then(data => {
                const footerBuild = document.getElementById('yue_footer_build_no');
                const footerDevice = document.getElementById('yue_footer_device');
                const footerMem = document.getElementById('yue_footer_memory');

                const headerDevBadge = document.getElementById('yue_header_device_badge');
                const headerRamBadge = document.getElementById('yue_header_ram_badge');

                if (footerBuild) footerBuild.textContent = `Build: ${data.build_number}`;
                if (footerDevice) footerDevice.textContent = `Device: ${data.device}`;
                if (footerMem) footerMem.textContent = `RAM: ${data.used_ram_gb} GB / ${data.total_ram_gb} GB (${data.ram_percent}%)`;

                if (headerDevBadge) headerDevBadge.textContent = `⚡ ${data.device}`;
                if (headerRamBadge) headerRamBadge.textContent = `💾 RAM: ${data.used_ram_gb} GB / ${data.total_ram_gb} GB`;

                const modelDirInput = document.getElementById('yue_setting_models_path');
                if (modelDirInput && !modelDirInput.value) {
                    modelDirInput.value = data.models_dir;
                }
            })
            .catch(err => console.error('Status fetch error:', err));
    }
    loadSystemStatus();
    setInterval(loadSystemStatus, 10000);

    // 4. Load Presets (User Rule 4)
    function loadPresets() {
        // Genres
        fetch('/api/presets/genres')
            .then(res => res.json())
            .then(genres => {
                const container = document.getElementById('yue_genre_presets_container');
                if (!container) return;
                container.innerHTML = '';
                genres.forEach(g => {
                    const chip = document.createElement('div');
                    chip.className = 'yue_chip';
                    chip.textContent = g.name;
                    chip.title = g.tags;
                    chip.addEventListener('click', () => {
                        const genreInput = document.getElementById('yue_genre_input');
                        if (genreInput) {
                            genreInput.value = g.tags;
                        }
                    });
                    container.appendChild(chip);
                });
            })
            .catch(err => console.error('Presets error:', err));

        // Lyrics
        fetch('/api/presets/lyrics')
            .then(res => res.json())
            .then(lyrics => {
                const select = document.getElementById('yue_lyrics_presets_select');
                if (!select) return;
                select.innerHTML = '<option value="">-- Load a Lyrics Preset Template --</option>';
                lyrics.forEach(l => {
                    const opt = document.createElement('option');
                    opt.value = l.id;
                    opt.textContent = l.title;
                    opt.dataset.lyrics = l.lyrics;
                    select.appendChild(opt);
                });

                select.addEventListener('change', (e) => {
                    const selected = select.options[select.selectedIndex];
                    const lyricsTextarea = document.getElementById('yue_lyrics_textarea');
                    if (selected && selected.dataset.lyrics && lyricsTextarea) {
                        lyricsTextarea.value = selected.dataset.lyrics;
                    }
                });
            })
            .catch(err => console.error('Lyrics error:', err));
    }
    loadPresets();

    // 5. Load Settings (User Rule 3)
    function loadSettings() {
        fetch('/api/settings')
            .then(res => res.json())
            .then(settings => {
                if (settings.default_temperature) {
                    setSliderVal('yue_param_temp', 'yue_param_temp_val', settings.default_temperature);
                }
                if (settings.default_top_p) {
                    setSliderVal('yue_param_topp', 'yue_param_topp_val', settings.default_top_p);
                }
                if (settings.default_cfg_scale) {
                    setSliderVal('yue_param_cfg', 'yue_param_cfg_val', settings.default_cfg_scale);
                }
                if (settings.default_max_tokens) {
                    const sec = Math.max(10, Math.min(300, Math.round(parseInt(settings.default_max_tokens) / 100)));
                    const secSlider = document.getElementById('yue_param_seconds');
                    if (secSlider) secSlider.value = sec;
                    window.yue_updateDurationDisplay(sec);
                }
                if (settings.stage2_quality) {
                    const qSelect = document.getElementById('yue_param_quality');
                    if (qSelect) qSelect.value = settings.stage2_quality;
                }
                if (settings.auto_unload_stage1 !== undefined) {
                    const unloadChk = document.getElementById('yue_setting_unload_stage1');
                    if (unloadChk) unloadChk.checked = settings.auto_unload_stage1;
                }
            })
            .catch(err => console.error('Settings error:', err));
    }
    loadSettings();

    function setSliderVal(sliderId, valId, val) {
        const slider = document.getElementById(sliderId);
        const label = document.getElementById(valId);
        if (slider) slider.value = val;
        if (label) label.textContent = val;
    }

    // Connect slider displays
    const sliderBindings = [
        ['yue_param_temp', 'yue_param_temp_val'],
        ['yue_param_topp', 'yue_param_topp_val'],
        ['yue_param_cfg', 'yue_param_cfg_val'],
        ['yue_param_width', 'yue_param_width_val']
    ];

    sliderBindings.forEach(([sId, vId]) => {
        const slider = document.getElementById(sId);
        const label = document.getElementById(vId);
        if (slider && label) {
            slider.addEventListener('input', (e) => {
                label.textContent = e.target.value;
            });
        }
    });

    const secondsSlider = document.getElementById('yue_param_seconds');
    if (secondsSlider) {
        secondsSlider.addEventListener('input', (e) => {
            window.yue_updateDurationDisplay(e.target.value);
        });
    }

    // 6. Generation Handling
    const btnGenerate = document.getElementById('yue_btn_generate');
    const btnCancel = document.getElementById('yue_btn_cancel');
    const progressBox = document.getElementById('yue_progress_box');
    const progressFill = document.getElementById('yue_progress_fill');
    const progressPhase = document.getElementById('yue_progress_phase');
    const progressMsg = document.getElementById('yue_progress_msg');
    const linkViewNotes = document.getElementById('yue_link_view_notes');

    if (linkViewNotes) {
        linkViewNotes.addEventListener('click', (e) => {
            e.preventDefault();
            const navScore = document.getElementById('yue_nav_score');
            if (navScore) navScore.click();
        });
    }

    let pollInterval = null;

    if (btnGenerate) {
        btnGenerate.addEventListener('click', () => {
            const title = document.getElementById('yue_song_title_input')?.value || 'Untitled Song';
            const genre = document.getElementById('yue_genre_input')?.value || '';
            const lyrics = document.getElementById('yue_lyrics_textarea')?.value || '';

            if (!genre.trim() || !lyrics.trim()) {
                alert('Please enter both genre tags and lyrics.');
                return;
            }

            const targetSeconds = parseInt(document.getElementById('yue_param_seconds')?.value || 15);

            const payload = {
                title: title,
                genre_tags: genre,
                lyrics: lyrics,
                temperature: parseFloat(document.getElementById('yue_param_temp')?.value || 0.9),
                top_p: parseFloat(document.getElementById('yue_param_topp')?.value || 0.95),
                cfg_scale: parseFloat(document.getElementById('yue_param_cfg')?.value || 1.5),
                target_seconds: targetSeconds,
                max_tokens: targetSeconds * 100,
                seed: parseInt(document.getElementById('yue_param_seed')?.value || 42),
                stage2_quality: document.getElementById('yue_param_quality')?.value || 'full',
                stereo_width: parseFloat(document.getElementById('yue_param_width')?.value || 0.5),
                apply_mastering: document.getElementById('yue_param_mastering')?.checked ?? true,
                cot_mode: document.getElementById('yue_param_cot_mode')?.value || 'off',
                custom_abc: scoreViewer.abcEditor ? scoreViewer.abcEditor.value : null
            };

            btnGenerate.disabled = true;
            if (btnCancel) btnCancel.style.display = 'inline-flex';
            if (progressBox) progressBox.style.display = 'block';

            fetch('/api/generate', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            })
            .then(res => {
                if (!res.ok) return res.json().then(d => { throw new Error(d.detail || 'Generation start failed'); });
                return res.json();
            })
            .then(data => {
                startProgressPolling();
            })
            .catch(err => {
                alert('Error: ' + err.message);
                resetGenControls();
            });
        });
    }

    if (btnCancel) {
        btnCancel.addEventListener('click', () => {
            fetch('/api/cancel', { method: 'POST' })
                .then(() => {
                    resetGenControls();
                });
        });
    }

    function startProgressPolling() {
        if (pollInterval) clearInterval(pollInterval);
        pollInterval = setInterval(() => {
            fetch('/api/generate/progress')
                .then(res => res.json())
                .then(prog => {
                    if (progressPhase) progressPhase.textContent = prog.phase || 'Generating';
                    if (progressMsg) progressMsg.textContent = prog.message || '';
                    if (progressFill) progressFill.style.width = Math.round((prog.progress_fraction || 0) * 100) + '%';

                    if (prog.status === 'completed') {
                        clearInterval(pollInterval);
                        resetGenControls();
                        if (prog.audio_url) {
                            waveformPlayer.loadAudio(prog.audio_url);
                            waveformPlayer.togglePlay();
                        }
                        if (prog.abc_score) {
                            scoreViewer.renderFromAbc(prog.abc_score);
                            const badge = document.getElementById('yue_score_ready_badge');
                            const notif = document.getElementById('yue_score_notification');
                            if (badge) badge.style.display = 'inline-block';
                            if (notif) notif.style.display = 'block';
                        }
                        loadHistory();
                    } else if (prog.status === 'failed' || prog.status === 'idle') {
                        clearInterval(pollInterval);
                        resetGenControls();
                        if (prog.status === 'failed') {
                            alert('Generation error: ' + prog.message);
                        }
                    }
                })
                .catch(err => console.error('Poll error:', err));
        }, 1000);
    }

    function resetGenControls() {
        if (btnGenerate) btnGenerate.disabled = false;
        if (btnCancel) btnCancel.style.display = 'none';
    }

    // 7. Library / History
    function loadHistory() {
        fetch('/api/history')
            .then(res => res.json())
            .then(records => {
                const tbody = document.getElementById('yue_history_tbody');
                if (!tbody) return;
                tbody.innerHTML = '';
                if (!records.length) {
                    tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: #94a3b8;">No generations found.</td></tr>';
                    return;
                }

                records.forEach(r => {
                    const tr = document.createElement('tr');
                    tr.innerHTML = `
                        <td><strong>${escapeHtml(r.title)}</strong></td>
                        <td><span style="color: #06b6d4;">${r.duration_seconds.toFixed(1)}s</span></td>
                        <td style="max-width: 260px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${escapeHtml(r.genre_tags)}</td>
                        <td>${new Date(r.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</td>
                        <td>
                            <button class="yue_btn" style="padding: 4px 8px; font-size: 11px;" onclick="window.yue_playTrack('${r.audio_url}')">▶ Play</button>
                            <a href="${r.audio_url}" download class="yue_btn" style="padding: 4px 8px; font-size: 11px; text-decoration: none;">⬇ WAV</a>
                        </td>
                    `;
                    tbody.appendChild(tr);
                });
            })
            .catch(err => console.error('History load error:', err));
    }

    window.yue_playTrack = function(url) {
        waveformPlayer.loadAudio(url);
        waveformPlayer.togglePlay();
    };

    function escapeHtml(text) {
        if (!text) return '';
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // 8. Save Settings
    const btnSaveSettings = document.getElementById('yue_btn_save_settings');
    if (btnSaveSettings) {
        btnSaveSettings.addEventListener('click', () => {
            const payload = {
                settings: {
                    model_directory_path: document.getElementById('yue_setting_models_path')?.value || '',
                    auto_unload_stage1: document.getElementById('yue_setting_unload_stage1')?.checked ?? true,
                    default_temperature: parseFloat(document.getElementById('yue_param_temp')?.value || 0.9),
                    default_top_p: parseFloat(document.getElementById('yue_param_topp')?.value || 0.95),
                    default_cfg_scale: parseFloat(document.getElementById('yue_param_cfg')?.value || 1.5),
                    stage2_quality: document.getElementById('yue_param_quality')?.value || 'full'
                }
            };

            fetch('/api/settings', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            })
            .then(res => res.json())
            .then(() => alert('Settings saved to database!'))
            .catch(err => alert('Save settings failed: ' + err));
        });
    }
});
