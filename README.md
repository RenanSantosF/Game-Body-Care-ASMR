# Gross to Glow

Jogo mobile 3D (Godot 4.3) de clínica **nojenta e satisfatória**: pacientes chegam
com a mão ou o pé cheios de problemas, você escolhe a ferramenta certa, trata com
cuidado e vê o **antes e depois**.

- **Tela vertical (retrato)**. Mão e pé **suaves e orgânicos** (malha gerada por SDF), deitados num travesseiro, câmera de cima
- Lesões desenhadas por shader: pus brilhante, sangue, sujeira, crostas, calos, ferida com buracos, larvas, vermes, unhas
- Limpeza "de verdade": o pano/algodão apaga só onde você esfrega
- Animações de furar, espremer (o pus sai em fio), cortar seguindo a linha, raspar, lixar, puxar, cortar unha
- **Dor do paciente**: ferramenta errada machuca e piora, puxar rápido dói, trabalhar em área suja dói mais.
  O rostinho reage, chora e reclama. Dor em 100% = o paciente vai embora (perde a fase)
- Moedas, loja, desbloqueio e melhoria de ferramentas, bônus diário, casos extremos
- Anúncios recompensados e intersticiais (modo simulado pronto; AdMob plugável)

## Realismo (como foi feito)

| Técnica | Onde | Efeito |
|---|---|---|
| Luz de pele com espalhamento subsuperficial (wrap + terminador avermelhado) e 2 lóbulos especulares | `shaders/lighting.gdshaderinc` | pele que "brilha por dentro", oleosidade |
| Microrrelevo procedural (poros, rugas finas, veias, manchas) convertido em normal | `shaders/skin.gdshader` | pele com textura de verdade sem imagens |
| Campo de altura por lesão → normal por diferenças finitas | `shaders/lesion.gdshader` | crateras afundadas, bordas inchadas, crosta em relevo |
| Pele deformável (uniforms globais) | `shaders/deform.gdshaderinc` | afunda sob o espremedor/pano, a pinça "puxa" a pele |
| Mapa de corte pintado ao vivo (`FxMap`) | `scripts/fxmap.gd` | o corte aparece exatamente onde a lâmina passa, abre com o tempo, sangue brota ao longo da linha e escorre |
| Inchaço com perfil suave (sem quina) e pele translúcida | `MeshGen.bump()` + `shaders/dome.gdshader` | espinhas/furúnculos que nascem da pele, murcham com rugas ao espremer |
| Gotas físicas | `Body.spawn_drops` | pus/sangue voam, caem e mancham a pele onde pousam (limpáveis) |
| Limpeza por máscara + brilho molhado que seca | `CleanMask` + uniform `wet` | o pano limpa só onde passa e deixa a pele molhada |
| Pano com trama e algodão com fibras que se sujam | `shaders/fabric.gdshader` | a ferramenta pega a cor do que limpou |

## Como abrir

1. Instale o **Godot 4.3** (PC) ou o **Godot Editor 4.3 para Android**.
2. Abra a pasta do projeto (`project.godot`) e rode. A cena inicial é `scenes/main_menu.tscn`.

Renderizador: **Compatibility (OpenGL ES 3)**, sem sombras dinâmicas (sombra de contato pré-calculada) — leve no Android.

## Controles

| Gesto | Ação |
|---|---|
| 1 dedo | **mira** a ferramenta (ela fica acima e à esquerda do dedo). Mirar não faz nada sozinho |
| 2º dedo em qualquer lugar | **usa** a ferramenta: fura, corta, limpa, raspa, espreme, puxa, cola o curativo |
| PC | botão esquerdo = mirar, **direito ou Espaço = usar** |

A câmera é automática: ao terminar um problema ela vai sozinha para o próximo (a seta e o anel
de progresso mostram onde e quanto falta). Só ferramentas que machucam (agulha, bisturi,
alicate, lâmina, raspador, lixa, espremedor, pinça) causam dor se usadas no lugar errado.
Furar/cortar pele saudável cria um machucado que precisa de algodão e curativo.

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
| 2 | Cisto sebáceo | Agulha → Espremedor (sai a "massa") → Algodão |
| 2 | Ralado com sujeira | Pinça (pedrinhas) → Pano → Pomada → Curativo |
| 2 | Espinhos de cacto | Pinça (um por um) → Algodão |
| 2 | Unha roxa (sangue preso) | Agulha → Algodão |
| 3 | Abscesso enorme | Bisturi → Espremedor → Algodão → Curativo |
| 3 | Bicho-de-pé (só pé) | Agulha → Pinça (puxar) → Algodão → Curativo |

Cada problema sai com tamanho e cor de pus/sangue diferentes, e a mesma fase evita repetir o que saiu na anterior.
Pano e algodão continuam limpando a sujeira que sobrou mesmo depois do problema estar "pronto".

### v0.9: corpo inteiro e erros com consequência

- **Partes do corpo**: mão, pé, **costas** (de bruços, coluna e escápulas), **rosto** (nariz, lábios, sobrancelhas, barba) e **cabeça** (couro cabeludo com cabelo denso). Geradas por SDF em `tools/bodygen.py` (malhas leves, ~30–37 mil vértices).
- **Problemas novos**: carbúnculo com várias cabeças de pus, acne inflamada, queimadura com bolhas e pele soltando, pontos infeccionados, piolhos andando + lêndeas, caspa grossa, barba enorme.
- **Ferramenta errada em cima do machucado** piora ali mesmo: corta/esfola onde você arrasta, sangra, inflama mais, custa 10 moedas e cria etapas extras (limpar o sangue e curativo).
- **Animações**: inflamação latejando, caroço estufa antes de estourar, paciente recua de dor e treme com dor alta, sangue empoça na pele plana e só escorre onde é inclinado.

### Sensações (v0.8)

- **Vibração** com força variável: cresce enquanto espreme/puxa, pulso seco a cada "nhec" do alicate, forte quando dói ou estoura.
- **Sons molhados** gerados por síntese de bolhas, com várias versões sorteadas (sem repetir sempre o mesmo).
- **Fio de pus contínuo** (`PusString`): sai do poro enquanto espreme, faz a curva, deita enrolando na pele e, ao soltar, desaba e vira mancha que dá para limpar.
- **Corte de unha progressivo**: sulco aparece onde o alicate já passou, a ponta solta levanta, a lasca cai na pele/toalha e quica; borda nova fica branca e áspera.
- **Pano moldado à pele**: cada ponto do tecido fica sempre acima da superfície.
- **Antes/depois com slider** arrastável e botão **Compartilhar** (salva a foto em Imagens/GrossToGlow e abre no visualizador).
- **Paciente chefe** a cada 5 fases: 10–12 problemas misturados, nome próprio e recompensa x3 + 150.

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

## APK (GitHub Actions)

O workflow `.github/workflows/android.yml` gera o APK a cada push:
**Actions → Build Android APK → (execução) → Artifacts → GrossToGlow-apk**.
Criando uma tag `v*` (ex.: `v0.3.0`) o APK também vai para a página de **Releases**.

- Assinado com chave de debug (instalação direta no celular, "fontes desconhecidas").
- Para manter a mesma assinatura entre builds (atualizar sem desinstalar), salve um keystore
  em base64 no segredo `ANDROID_KEYSTORE_B64` (alias `androiddebugkey`, senha `android`).
- Para a Play Store será preciso um keystore de release e AAB (Gradle build).

## Arte e música

- Logo e ícone: `tools/make_art.py` (PIL) com a fonte Lilita One; textos usam Fredoka (ambas OFL).
- Ícones das ferramentas: renderizados dos próprios modelos 3D (`autoload/icons.gd`).
- Músicas compostas por síntese própria em `tools/compose.py` (lo-fi da clínica e tema do menu).
