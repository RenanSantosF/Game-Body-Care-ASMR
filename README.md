# Gross to Glow

Jogo mobile 3D (Godot 4.3) de clínica **nojenta e satisfatória**: receba pacientes
cheios de problemas na pele, escolha a ferramenta certa, trate tudo e veja o
**antes e depois**.

- Low poly, colorido, 100% gerado por código (sem assets externos — leve e fácil de editar no celular)
- Horizontal, controles por toque/arraste, câmera aproximada no problema
- 20 tipos de problema, 10 ferramentas, fases infinitas, casos extremos, combos
- Moedas, loja com desbloqueio e melhoria de ferramentas, bônus diário
- Anúncios recompensados e intersticiais (modo simulado pronto; AdMob plugável)

## Como abrir

1. Instale o **Godot 4.3** (PC) ou o **Godot Editor 4.3 para Android** (Play Store / site oficial).
2. Abra a pasta do projeto (`project.godot`).
3. Rode (F5 / botão Play). A cena inicial é `scenes/main_menu.tscn`.

Renderizador: **Compatibility (OpenGL ES 3)** — o mais compatível e rápido em Android fraco.

## Como jogar

1. Toque numa ferramenta na barra de baixo.
2. Toque/arraste no problema. Cada problema pode ter várias **etapas**:
   - **Segurar** (espremer, congelar) · **Esfregar** (escova, algodão, espátula)
   - **Cortar** (bisturi) · **Puxar devagar** (pinça) · **Tocar** (curativo)
   - **Passar por cima** (lâmina, pente) · **Pegar um por um** (larvas, espinhas)
3. Ferramenta errada = "AI!" e perde estrela. 0 erros = 3 estrelas.
4. Botão **Zoom** alterna visão geral/aproximada; **Dica (AD)** mostra a ferramenta certa por 30 s.

## Problemas (do simples ao bem nojento)

| Tier | Problema | Etapas |
|---|---|---|
| 1 | Espinha | Espremedor (segurar) → Algodão |
| 1 | Farpa | Pinça (puxar) |
| 1 | Sujeira | Escova |
| 1 | Cravo | Espátula |
| 1 | Chiclete grudado | Espátula |
| 2 | Capa de pus | Bisturi (cortar) → Espremedor → Algodão |
| 2 | Ninho de espinhas | Espremedor (uma por uma) → Algodão |
| 2 | Poros entupidos | Espátula (passar por cima) |
| 2 | Lama grossa | Escova → Algodão |
| 2 | Pelos crescidos misturados | Lâmina (passar por cima) |
| 2 | Pelo encravado | Pinça → Algodão |
| 2 | Crosta seca | Espátula → Algodão |
| 2 | Carrapato | Pinça → Algodão |
| 3 | Furúnculo gigante | Bisturi → Espremedor → Algodão → Curativo |
| 3 | Verme na pele | Pinça (puxar longo) → Algodão → Curativo |
| 3 | Berne | Espremedor → Pinça → Curativo |
| 3 | Ferida com larvas | Pinça (uma por uma) → Algodão → Curativo |
| 3 | Verruga | Spray gelo → Espátula |
| 3 | Sanguessuga | Spray gelo → Pinça → Algodão |
| 3 | Pulgas | Pente fino |

Fases 1–3 só tier 1, 4–8 até tier 2, 9+ tudo. **A cada 5 fases: CASO EXTREMO** (mais problemas, moedas em dobro).

## Estrutura

```
autoload/game_data.gd   save, moedas, ferramentas, bônus diário
autoload/sfx.gd         sons sintetizados por código
autoload/ad_manager.gd  anúncios (simulado + ganchos para AdMob)
scripts/defs.gd         DADOS: ferramentas, problemas, etapas, nomes
scripts/level_gen.gd    gera cada fase (determinístico por número)
scripts/patient.gd      monta rosto / braço / costas / pé
scripts/problem.gd      visual + comportamento de cada problema
scripts/tool_model.gd   ferramenta 3D que segue o dedo
scripts/tool_icon.gd    ícones 2D das ferramentas
scripts/game.gd         tela de jogo, câmera, entrada, HUD, resultado
scripts/main_menu.gd    menu, fases, loja, opções, bônus diário
```

### Adicionar um problema novo

1. Em `scripts/defs.gd` adicione em `PROBLEMS` (nome, tier, tamanho, peso e etapas).
2. Em `scripts/problem.gd` crie `_build_<id>()` e, se quiser, trate o visual em `_visual()` e os estouros em `_on_stage_end()`.

## Monetização

| Onde | Tipo |
|---|---|
| Resultado: "x2 Moedas" | Recompensado |
| Menu: "+60 grátis" | Recompensado |
| Bônus diário "x3" | Recompensado |
| Desbloquear ferramenta nova grátis | Recompensado |
| Dica durante o tratamento | Recompensado |
| A cada 3 pacientes (ao tocar em "Próximo") | Intersticial — nunca no meio do tratamento |

### Anúncios reais (AdMob)

Hoje `Ads` roda em **modo simulado** (tela falsa de 3 s). Para anúncios reais:

1. Instale um plugin AdMob para Godot 4 (ex.: *Poing Studios godot-admob-plugin*, pela AssetLib).
2. Configure o App ID no plugin e ative **Use Gradle Build** no preset Android.
3. Em `autoload/ad_manager.gd`, faça `use_real_ads()` retornar `true` e implemente
   `_real_show_rewarded` / `_real_show_interstitial` com a API do plugin
   (chamar `on_reward.call()` apenas quando o usuário ganhar a recompensa).
4. Troque os IDs de teste (`REWARDED_ID`, `INTERSTITIAL_ID`) pelos seus.

## Exportar para Android

`Projeto > Exportar > Adicionar > Android`, orientação já está em paisagem (sensor).
Precisa do Android SDK/JDK configurados (no PC). O editor Android do Godot 4.3 é
ótimo para editar e testar, mas a geração do APK/AAB é mais garantida pelo PC.

## Teste automático

Joga 25 fases sozinho (todos os 20 tipos de problema) e mostra erros no console:

```
godot --headless --path . res://tests/test_runner.tscn
```
