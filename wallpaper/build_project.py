"""Genera project.json con le opzioni del pannello in italiano e inglese.

Wallpaper Engine mostra i testi nella lingua dell'utente usando la sezione "localization".
Uso: python build_project.py
"""
import json
from pathlib import Path

IND, IND2 = '&nbsp;&nbsp;', '&nbsp;&nbsp;&nbsp;&nbsp;'

# (chiave, tipo, valore, italiano, inglese, extra)
PROPS = [
    ('language', 'combo', 'auto', '<b>Lingua</b>', '<b>Language</b>',
     {'options': [('auto', 'Automatica', 'Automatic'), ('it', 'Italiano', 'Italiano'), ('en', 'English', 'English')]}),
    ('editmode', 'bool', False, '<b>Modalità modifica</b> (sposta e ridimensiona i widget)',
     '<b>Edit mode</b> (move and resize widgets)', {}),
    ('snapgrid', 'bool', True, IND + 'Griglia magnetica', IND + 'Snap to grid', {}),
    ('gridsize', 'slider', 20, IND + 'Passo griglia (px)', IND + 'Grid size (px)',
     {'min': 8, 'max': 80, 'step': 2, 'condition': 'snapgrid.value == true'}),

    ('theme', 'combo', 'dark', '<b>Tema</b>', '<b>Theme</b>',
     {'options': [('dark', 'Scuro', 'Dark'), ('light', 'Chiaro', 'Light'), ('neon', 'Neon', 'Neon'),
                  ('glass', 'Vetro', 'Glass'), ('amoled', 'AMOLED (nero puro)', 'AMOLED (pure black)')]}),
    ('accentcolor', 'color', '0.35 0.82 1', 'Colore principale', 'Main color', {}),
    ('accentcolor2', 'color', '0.69 0.49 1', 'Colore secondario', 'Secondary color', {}),
    ('font', 'combo', 'segoe', 'Carattere', 'Font',
     {'options': [('segoe', 'Segoe UI (moderno)', 'Segoe UI (modern)'), ('bahn', 'Bahnschrift (squadrato)', 'Bahnschrift (squared)'),
                  ('cascadia', 'Cascadia Code (tecnico)', 'Cascadia Code (technical)'),
                  ('consolas', 'Consolas (monospazio)', 'Consolas (monospace)'), ('georgia', 'Georgia (elegante)', 'Georgia (elegant)')]}),
    ('uiscale', 'slider', 100, 'Dimensione interfaccia (%)', 'Interface size (%)', {'min': 50, 'max': 150, 'step': 5}),
    ('autofit', 'bool', True, IND + 'Adatta automaticamente allo schermo', IND + 'Auto-fit to screen', {}),
    ('cardopacity', 'slider', 100, 'Opacità riquadri (%)', 'Card opacity (%)', {'min': 0, 'max': 300, 'step': 10}),
    ('showsky', 'bool', True, 'Via Lattea di sfondo', 'Milky Way background', {}),
    ('backgroundimage', 'file', '', 'Oppure una tua immagine', 'Or your own image', {}),
    ('backgrounddim', 'slider', 15, IND + 'Oscura sfondo (%)', IND + 'Darken background (%)', {'min': 0, 'max': 100, 'step': 5}),
    ('nightdim', 'bool', False, 'Attenua di notte', 'Dim at night', {}),
    ('nightfrom', 'slider', 23, IND + 'Dalle ore', IND + 'From hour', {'min': 0, 'max': 23, 'step': 1, 'condition': 'nightdim.value == true'}),
    ('nightto', 'slider', 7, IND + 'Alle ore', IND + 'To hour', {'min': 0, 'max': 23, 'step': 1, 'condition': 'nightdim.value == true'}),
    ('nightlevel', 'slider', 50, IND + 'Intensità (%)', IND + 'Strength (%)', {'min': 10, 'max': 90, 'step': 5, 'condition': 'nightdim.value == true'}),

    ('showgreeting', 'bool', True, '<b>Saluto</b>', '<b>Greeting</b>', {}),
    ('showname', 'bool', True, IND + 'Con il nome', IND + 'With your name', {'condition': 'showgreeting.value == true'}),
    ('customname', 'textinput', '', IND + 'Nome (vuoto = account Windows)', IND + 'Name (empty = Windows account)',
     {'condition': 'showgreeting.value == true && showname.value == true'}),

    ('showclock', 'bool', True, '<b>Orologio</b>', '<b>Clock</b>', {}),
    ('clockstyle', 'combo', 'digital', IND + 'Stile', IND + 'Style',
     {'options': [('digital', 'Digitale', 'Digital'), ('analog', 'Analogico', 'Analog'), ('both', 'Entrambi', 'Both')],
      'condition': 'showclock.value == true'}),
    ('use24h', 'bool', True, IND + 'Formato 24 ore', IND + '24-hour format', {'condition': 'showclock.value == true'}),
    ('showseconds', 'bool', True, IND + 'Mostra secondi', IND + 'Show seconds', {'condition': 'showclock.value == true'}),
    ('analognumbers', 'bool', True, IND + 'Numeri sul quadrante analogico', IND + 'Numbers on analog dial', {'condition': 'showclock.value == true'}),

    ('showdate', 'bool', True, '<b>Data</b>', '<b>Date</b>', {}),
    ('showyear', 'bool', True, IND + "Con l'anno", IND + 'With year', {'condition': 'showdate.value == true'}),
    ('showweek', 'bool', True, 'Numero settimana', 'Week number', {}),
    ('showdayofyear', 'bool', True, "Giorno dell'anno", 'Day of year', {}),

    ('showweather', 'bool', True, '<b>Meteo</b>', '<b>Weather</b>', {}),
    ('weathercity', 'textinput', '', IND + 'Città', IND + 'City', {'condition': 'showweather.value == true'}),
    ('showforecast', 'bool', True, IND + 'Previsioni prossimi giorni', IND + 'Forecast', {'condition': 'showweather.value == true'}),
    ('showsun', 'bool', True, IND + 'Alba e tramonto', IND + 'Sunrise and sunset', {'condition': 'showweather.value == true'}),

    ('showmusic', 'bool', True, '<b>Musica</b> (Spotify e altri)', '<b>Music</b> (Spotify and others)', {}),
    ('musichideidle', 'bool', False, IND + 'Nascondi quando non suona niente', IND + 'Hide when nothing is playing',
     {'condition': 'showmusic.value == true'}),
    ('musiccolors', 'bool', False, IND + 'Colori dalla copertina', IND + 'Colors from album art', {'condition': 'showmusic.value == true'}),

    ('showcpu', 'bool', True, '<b>Prestazioni</b>: CPU', '<b>Performance</b>: CPU', {}),
    ('showram', 'bool', True, '<b>Prestazioni</b>: RAM', '<b>Performance</b>: RAM', {}),
    ('showgpu', 'bool', True, '<b>Prestazioni</b>: GPU', '<b>Performance</b>: GPU', {}),

    ('showsensors', 'bool', True, '<b>Sensori</b> (LibreHardwareMonitor)', '<b>Sensors</b> (LibreHardwareMonitor)', {}),
    ('showtemps', 'bool', True, IND + 'Temperature', IND + 'Temperatures', {'condition': 'showsensors.value == true'}),
    ('showfreq', 'bool', True, IND + 'Frequenze e consumi', IND + 'Clocks and power', {'condition': 'showsensors.value == true'}),
    ('showvram', 'bool', True, IND + 'Memoria video', IND + 'Video memory', {'condition': 'showsensors.value == true'}),
    ('showcores', 'bool', True, IND + 'Carico per core', IND + 'Per-core load', {'condition': 'showsensors.value == true'}),
    ('showfans', 'bool', True, IND + 'Ventole', IND + 'Fans', {'condition': 'showsensors.value == true'}),
    ('fansactive', 'bool', True, IND2 + 'Solo ventole che girano', IND2 + 'Only spinning fans',
     {'condition': 'showsensors.value == true && showfans.value == true'}),

    ('showdisks', 'bool', True, '<b>Dischi</b>', '<b>Drives</b>', {}),
    ('showdiskio', 'bool', True, IND + 'Velocità lettura / scrittura', IND + 'Read / write speed', {'condition': 'showdisks.value == true'}),
    ('showdisktemp', 'bool', True, IND + 'Temperatura dischi', IND + 'Drive temperature', {'condition': 'showdisks.value == true'}),

    ('shownetwork', 'bool', True, '<b>Rete</b>', '<b>Network</b>', {}),
    ('showping', 'bool', True, IND + 'Ping', IND + 'Ping', {'condition': 'shownetwork.value == true'}),

    ('showtop', 'bool', True, '<b>Programmi più pesanti</b>', '<b>Top processes</b>', {}),
    ('toptype', 'combo', 'both', IND + 'Mostra', IND + 'Show',
     {'options': [('both', 'CPU e RAM', 'CPU and RAM'), ('cpu', 'Solo CPU', 'CPU only'), ('ram', 'Solo RAM', 'RAM only')],
      'condition': 'showtop.value == true'}),
    ('topcount', 'slider', 5, IND + 'Quanti programmi', IND + 'How many', {'min': 3, 'max': 8, 'step': 1, 'condition': 'showtop.value == true'}),

    ('showsysinfo', 'bool', True, '<b>Sistema</b>', '<b>System</b>', {}),
    ('showhost', 'bool', True, IND + 'Nome computer', IND + 'Computer name', {'condition': 'showsysinfo.value == true'}),
    ('showos', 'bool', True, IND + 'Sistema operativo', IND + 'Operating system', {'condition': 'showsysinfo.value == true'}),
    ('showcpuname', 'bool', True, IND + 'Processore', IND + 'Processor', {'condition': 'showsysinfo.value == true'}),
    ('showgpuname', 'bool', True, IND + 'Scheda video', IND + 'Graphics card', {'condition': 'showsysinfo.value == true'}),
    ('showres', 'bool', True, IND + 'Risoluzione', IND + 'Resolution', {'condition': 'showsysinfo.value == true'}),
    ('showuptime', 'bool', True, IND + 'Acceso da', IND + 'Uptime', {'condition': 'showsysinfo.value == true'}),

    ('showaudio', 'bool', True, '<b>Barre audio</b>', '<b>Audio bars</b>', {}),
    ('showwarning', 'bool', True, 'Avviso helper non attivo', 'Helper not running notice', {}),
]

DESC_IT = ('Orologio, meteo, musica, sensori e informazioni di sistema, con la Via Lattea di sfondo. '
           'Pensato per monitor verticali.')

properties, it, en = {}, {}, {}
for order, (key, typ, value, label_it, label_en, extra) in enumerate(PROPS):
    ui = f'ui_vsc_{key}'
    it[ui], en[ui] = label_it, label_en
    prop = {'order': order, 'text': ui, 'type': typ, 'value': value}
    for k in ('min', 'max', 'step'):
        if k in extra:
            prop[k] = extra[k]
    if 'options' in extra:
        prop['options'] = []
        for val, o_it, o_en in extra['options']:
            ou = f'ui_vsc_{key}_{val}'
            it[ou], en[ou] = o_it, o_en
            prop['options'].append({'label': ou, 'value': val})
    if 'condition' in extra:
        prop['condition'] = extra['condition']
    properties[key] = prop

project = {
    'file': 'index.html',
    'title': 'Vertical System Clock',
    'description': DESC_IT,
    'type': 'web',
    'preview': 'preview.jpg',
    'contentrating': 'Everyone',
    'visibility': 'public',
    'tags': ['Technology'],
    'general': {
        'supportsaudioprocessing': True,
        'localization': {'it-it': it, 'en-us': en},
        'properties': properties,
    },
}

out = Path(__file__).with_name('project.json')
out.write_text(json.dumps(project, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'scritto {out.name}: {len(properties)} opzioni')
