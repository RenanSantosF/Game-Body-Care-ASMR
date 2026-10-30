# Gross to Glow

Jogo mobile 3D (Godot 4.3) de clínica **nojenta e satisfatória**: pacientes chegam
com a mão ou o pé cheios de problemas, você escolhe a ferramenta certa, trata com
cuidado e vê o **antes e depois**.

- Mão e pé **suaves e orgânicos** (malha gerada por SDF, sem cara de bloco), deitados num travesseiro, câmera de cima
- Lesões desenhadas por shader: pus brilhante, sangue, sujeira, crostas, calos, ferida com buracos, larvas, vermes, unhas
- Limpeza "de verdade": o pano/algodão apaga só onde você esfrega
- Animações de furar, espremer (o pus sai em fio), cortar seguindo a linha, raspar, lixar, puxar, cortar unha
- **Dor do paciente**: ferramenta errada machuca e piora, puxar rápido dói, trabalhar em área suja dói mais.
  O rostinho reage, chora e reclama. Dor em 100% = o paciente vai embora (perde a fase)
- Moedas, loja, desbloqueio e melhoria de ferramentas, bônus diário, casos extremos
- Anúncios recompensados e intersticiais (modo simulado pronto; AdMob plugável)

## Como abrir

1. Instale o **Godot 4.3** (PC) ou o **Godot Editor 4.3 para Android**.
2. Abra a pasta do projeto (`project.godot`) e rode. A cena inicial é `scenes/main_menu.tscn`.

Renderizador: **Compatibility (OpenGL ES 3)**, sem sombras dinâmicas (sombra de contato pré-calculada) — leve no Android.

## Como jogar

1. Toque numa ferramenta na barra de baixo e depois no problema.
2. Cada problema tem **etapas**. A dica no topo mostra a ação:
   - **Segurar** (agulha fura, espremedor espreme, spray congela)
   - **Esfregar a área toda** (pano, algodão, raspador, lixa, pomada)
   - **Cortar seguindo a linha pontilhada** (bisturi, alicate de unha)
   - **Puxar devagar** (pinça) · **Tocar** (curativo) · **Passar por cima** (lâmina) · **Pegar um por um**
3. **Limpe a sujeira com o pano antes**: perto de sujeira o tratamento fica mais lento e dói mais.
4. Ferramenta errada ou objeto afiado na pele saudável = machucado novo (sangra, precisa de algodão + curativo).
5. Estrelas pela dor máxima e erros. Se a dor chegar a 100%: "Acalmar e continuar (AD)" ou tentar de novo.

## Problemas

| Tier | Problema | Etapas |
|---|---|---|
| 1 | Espinha com pus | Agulha → Espremedor → Algodão |
| 1 | Bolha d'água | Agulha → Algodão → Curativo |
| 1 | Farpa | Pinça → Algodão |
| 1 | Sujeira grudada | Pano |
| 1 | Cravos | Espremedor (um por um) → Pano |
| 1 | Pelos crescidos | Lâmina |
| 2 | Pelo encravado | Agulha → Pinça → Algodão |
| 2 | Carrapato | Pinça → Algodão |
| 2 | Unha grande e suja | Alicate (cortar) → Pano |
| 2 | Unha inflamada com pus | Agulha → Espremedor → Algodão → Curativo |
| 2 | Casca de ferida | Algodão → Raspador → Pomada |
| 2 | Calo grosso (pé) | Raspador → Lixa → Pomada |
| 2 | Micose na unha | Lixa → Pomada |
| 3 | Furúnculo gigante | Bisturi (cortar) → Espremedor → Algodão → Curativo |
| 3 | Verme debaixo da pele | Bisturi (abrir o túnel) → Pinça → Algodão → Curativo |
| 3 | Ferida com larvas | Pano → Pinça (uma por uma) → Algodão → Pomada |
| 3 | Ferida cheia de buracos | Pano → Espremedor (cada buraco) → Algodão → Pomada |
| 3 | Unha encravada | Alicate → Pinça → Algodão → Curativo |
| 3 | Verruga | Spray gelo → Raspador → Pomada |

## Estrutura

```
autoload/            save/moedas, sons sintetizados, anúncios
assets/body/         malhas da mão e do pé + mapa de altura (gerados)
shaders/             pele, travesseiro, lesões, cúpulas (pus/bolha), unha, tubos (verme/pus)
scripts/body.gd      carrega mão/pé, superfície, unhas, sombra
scripts/problem.gd   visual + animação + etapas de cada problema
scripts/game.gd      câmera, entrada, dor, erros, HUD, resultado
scripts/meshgen.gd   tubos, remendos na pele, unhas, partículas
scripts/mask.gd      máscara de limpeza (esfregar apaga)
scripts/patient_face.gd   rostinho que reage
tools/bodygen.py     gera as malhas (Python, só no PC)
tools/convert_body.gd     converte para recursos do Godot
```

### Regerar a mão/pé (opcional, no PC)

```
pip install numpy scikit-image
python3 tools/bodygen.py
godot --headless --path . -s tools/convert_body.gd
```

### Adicionar um problema novo

1. `scripts/defs.gd` → `PROBLEMS` (nome, tier, tamanho, onde aparece, etapas).
2. `scripts/problem.gd` → `_build_<id>()`, e trate o visual em `_visual()` / `_on_stage_end()`.

## Monetização

| Onde | Tipo |
|---|---|
| Resultado: "x2 Moedas" | Recompensado |
| Menu: "+60 grátis" | Recompensado |
| Bônus diário "x3" | Recompensado |
| Ferramenta nova grátis | Recompensado |
| Dica durante o tratamento | Recompensado |
| Paciente foi embora: "Acalmar e continuar" | Recompensado |
| A cada 3 pacientes (ao tocar em "Próximo") | Intersticial |

### Anúncios reais (AdMob)

`Ads` roda em **modo simulado**. Para anúncios reais: instale um plugin AdMob para Godot 4
(ex.: *Poing Studios godot-admob-plugin*), faça `use_real_ads()` retornar `true` em
`autoload/ad_manager.gd` e implemente `_real_show_rewarded` / `_real_show_interstitial`.
Troque os IDs de teste pelos seus.

## Exportar para Android

`Projeto > Exportar > Android` (paisagem). Gerar APK/AAB é mais garantido pelo PC com Android SDK.

## Teste automático

Joga as fases sozinho e mostra erros no console:

```
godot --headless --path . res://tests/test_runner.tscn
```
