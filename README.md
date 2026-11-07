# Angry Birds Classic — Sega Master System (8-Bit) Port

Um port 8-bit completo e fiel do **Angry Birds Classic** (Episódio 1: *Poached Eggs* — todas as 21 fases originais) desenvolvido especificamente para o hardware real do **Sega Master System (Mark III / Master System I / II / III Compact)** em Assembly Zilog Z80 puro.

---

## Arquivos ROM Gerados (`sms/`)

| Arquivo | Tamanho | Uso Recomendado |
| :--- | :--- | :--- |
| **`angrybirds.sms`** | **64 KB** (`65.536` bytes) | **Emuladores** (Emulicious, Mesen, Kega Fusion, Gearsystem, RetroArch Genesis Plus GX / SMS Plus), **Master EverDrive / Flashcarts** e **EPROM 27C512 (64 KB)**. |
| **`angrybirds_32k.sms`** | **32 KB** (`32.768` bytes) | **EPROM 27C256 (32 KB)** para gravação direta em cartuchos doadores simples de 32 KB (sem chip Sega Mapper). |

Ambos os arquivos possuem cabeçalho oficial **`TMR SEGA`** em `$7FF0-$7FFF` com checksum de 16 bits validado (`$98BA`) e código de região `Export / 32KB` (`$4C`), garantindo boot imediato em qualquer BIOS nacional (TecToy) ou internacional (EUA / Europa / Japão).

---

## Controles (Controle do Master System + Console)

| Botão | Na Tela de Título | Durante o Jogo (Mirando) | Durante o Voo do Pássaro |
| :--- | :--- | :--- | :--- |
| **Cima / Baixo** | — | Ajusta o **Ângulo** do estilingue (`0..16`) | — |
| **Esquerda / Direita** | Seleciona a fase inicial (`01` a `21`) | Ajusta a **Força** da puxada (`6..16`) | — |
| **Botão 1** (`START` / `A`) | Inicia o jogo | **Dispara** o pássaro | Ativa o **Poder Especial** do pássaro |
| **Botão 2** (`B`) | Inicia o jogo | **Espiar o Castelo** (rola a câmera até os porcos; solte para voltar ao estilingue) | — |
| **Botão PAUSE** (no console) | Inicia o jogo | **Pausa / Despausa** a partida (via interrupção `NMI $0066`) | **Pausa / Despausa** a partida |

---

## Poderes Especiais dos Pássaros (`Botão 1` em voo)

1. **Red (Pássaro Vermelho)**: Grito de Guerra (*Battle Cry*) com efeito sonoro no PSG.
2. **The Blues (Pássaro Azul)**: Divide-se em **3 pássaros azuis simultâneos** com trajetórias em leque (superior, central e inferior) que destroem múltiplos blocos e gelo de uma só vez.
3. **Chuck (Pássaro Amarelo)**: **Turbo Dash** diagonal em alta velocidade (`VX * 2`), perfurando madeira com dano dobrado.
4. **Bomb (Pássaro Preto)**: **Explosão em Área (Radius 32px)** que destrói pedra, madeira, gelo, TNT e porcos ao redor, com flash de tela e estrondo no canal de ruído do SN76489.

---

## Características Técnicas de Hardware (Master System)

- **CPU**: Zilog Z80A @ 3,58 MHz (NTSC) / 3,55 MHz (PAL-M TecToy) em Assembly nativo:
  - Vetor de Reset em `$0000` (`DI`, `IM 1`, `LD SP, $DFF0`, inicialização dos registradores do Sega Mapper `$FFFC..$FFFF` e silenciamento imediato dos 4 canais do PSG `$7F`).
  - Vetor de Interrupção VBlank (`IRQ`) em `$0038` e Botão `PAUSE` (`NMI`) em `$0066`.
- **VDP (315-5124 / 315-5246 — Modo 4 Nativo 256×192)**:
  - Compatibilidade estrita com **Master System 1 real**: bits não usados dos registradores `R2 ($FF)`, `R3 ($FF)`, `R4 ($FF)`, `R5 ($FF)` e `R6 ($FB)` configurados em `1` para evitar máscaras de endereço corrompidas no silício original.
  - **HUD Fixo de 2 Linhas no Topo (`R0 = $46`)**: Utiliza o bit 6 do Registrador 0 do VDP (*Top-2-Row Horizontal Scroll Lock*) para manter o placar (`LVL`, `BIRDS`, `PIGS`, `SCORE`) travado no topo enquanto o cenário de `512×192` (`64×24` tiles) rola suavemente via `R8`.
  - **Streaming de Colunas em VBlank**: Toda atualização da nametable (`$3800`) e da Sprite Attribute Table (`$3F00`) ocorre exclusivamente dentro da janela de VBlank (máximo de 8 colunas sujas por quadro + 128 bytes do HUD), garantindo **zero corrupção de VRAM** no console real.
  - **Respeito ao Limite de 8 Sprites por Scanline**: Todos os blocos dos castelos e porcos descansando no cenário são desenhados no plano de Background (com prioridade e colisão por tile), reservando os sprites de hardware para os pássaros em voo, mira do estilingue, porcos/blocos em queda livre com gravidade pixel a pixel e partículas de explosão.
- **Áudio (SN76489 PSG — 4 Canais a 60 Hz)**:
  - **Canal 0 (Square 1)**: Melodia principal do *Angry Birds Balkan Theme* com vibrato/envelope estilo acordeão.
  - **Canal 1 (Square 2)**: Harmonia em terças/sextas e arpejos de bandolim.
  - **Canal 2 (Square 3)**: Linha de baixo (*Tuba Oom-Pah*) + efeitos sonoros melódicos.
  - **Canal 3 (Noise)**: Percussão (bumbo e caixa) + efeitos de explosão, impacto em madeira/pedra e estilingue.

---

## Como Jogar em Emuladores, Master EverDrive e Gravar em EPROM

### 1. Emuladores
Abra o arquivo `sms/angrybirds.sms` em qualquer emulador de Sega Master System:
- **Emulicious** (recomendado para precisão de ciclo e depuração)
- **Mesen** / **Gearsystem** / **Kega Fusion**
- **RetroArch** (núcleos *Genesis Plus GX*, *SMS Plus GX* ou *Gearsystem*)

### 2. Master EverDrive / Cartuchos SD
1. Copie o arquivo `sms/angrybirds.sms` para qualquer pasta do cartão SD do seu **Master EverDrive** (ou EverDrive-GG em modo Master System).
2. Ligue o console e selecione `angrybirds.sms` no menu. O jogo não requer bateria de save (SRAM) e inicializa o mapper padrão da Sega automaticamente.

### 3. Gravando em EPROM (Cartucho Físico Real)
- **Para placas doadoras simples de 32 KB (sem chip Sega Mapper 315-5235 / 315-5208)**:
  - Grave o arquivo **`sms/angrybirds_32k.sms`** (`32.768` bytes) em uma EPROM **27C256** (DIP-28, 32 KB × 8).
  - Em placas TecToy/Sega de 28 pinos para máscara de 32 KB, a pinagem é **100% direta (drop-in)** com a 27C256!
- **Para placas com EPROM 27C512 (64 KB) ou 27C010 (128 KB)**:
  - Grave o arquivo **`sms/angrybirds.sms`** (`65.536` bytes) diretamente em uma **27C512** (DIP-28).
  - Caso use uma placa sem mapper com uma **27C512**, aterre o pino `A15` (pino 1) ou grave `angrybirds.sms` (os primeiros 32 KB já contêm todo o jogo e o cabeçalho `TMR SEGA` em `$7FF0`).

---


