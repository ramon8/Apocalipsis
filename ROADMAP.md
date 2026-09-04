# Roadmap: el pueblo

Referencia: imagen del pueblo entre pinos con hoguera central, lago y molino.
Lo que ya existe: molino con interior, hoguera y minijuego, árboles, arbustos, heno,
banco, NPCs con diálogo por datos, perro, ciclo día-noche, viento.

Orden propuesto por impacto visual por hora de trabajo. Marca lo hecho.

## 1. Terreno

- [x] **Caminos de tierra desde `Path3D`.** Curvas en el editor; al cargar se rasterizan a
      una máscara que el shader del suelo mezcla con tierra. Ancho y suavidad por camino.
- [x] **Hierba verdosa a parches.** Sustituye a la hierba de blades (demasiado ruido).
      Manchas verdes sobre el suelo claro por ruido en el shader, más densas lejos de los
      caminos, con snap a paleta.
- [ ] **Lago.** Plano con shader: agua oscura, ondulación con el ruido del viento, espuma en
      la orilla por profundidad, snap a paleta. Juncos con un `ScatterArea` y el shader de
      hierba estirado. Rocas en la orilla.
- [ ] **Oscuridad en los bordes.** Niebla por distancia oscura en el `Environment` o
      vignette fuerte en el post del `RetroRenderer`.
- [ ] **Rocas y peñascos.** Modelo o procedural, vía `ScatterArea`.

## 2. Estructuras procedurales

- [ ] **Vallas por `Path3D`.** Postes cada N metros, dos travesaños, madera con el shader
      del banco, colisión por segmento. Cierra corrales dibujando la curva.
- [ ] **Campo de cultivo.** `ScatterArea` rectangular en rejilla con un tallo de trigo y el
      shader de viento de los arbustos.
- [ ] **Cobertizo abierto.** Tejado sobre postes, procedural como el banco.

## 3. Edificios (Blender + pipeline del molino)

- [ ] **Prop `Building` genérico.** GLB con colisión `-col`, shader de envejecido,
      `ModelMaterials`, `Room` opcional, lista de luces de ventana.
- [ ] **Casa de piedra** con ventana iluminada (material emisivo + `OmniLight3D` sin
      sombra ligada al ciclo día-noche). Variante con porche.
- [ ] **Iglesia** con campanario.
- [ ] **Torre de vigilancia** de madera con bandera (tela con el shader de viento).
- [ ] **Ruinas** de muros de piedra.

## 4. Props pequeños

- [ ] Pozo de piedra (centro del pueblo).
- [ ] Carro de madera.
- [ ] Poste indicador (interactuable: `InteractionZone` + bocadillo con el texto).
- [ ] Barriles, cajas y sacos junto a las casas.
- [ ] Muelle de madera y barca de remos (estáticos; navegar queda para más adelante).

## 5. Vida

- [ ] **Limpiar la state machine del perro** (`_sit_transition` y `_fire_focus` a estados
      reales) y sacar una base común.
- [ ] **Animales de corral** (oveja, cerdo): `IDLE / WANDER / GRAZE` con límite de zona.
- [ ] **Más NPCs** alrededor de la hoguera: escenas heredadas de `npc.tscn` con sus
      `DialogueEntry`. NPCs de pie con idle.

## 6. Iluminación nocturna

- [ ] Presupuesto de luces: la hoguera con sombra, ventanas y farolillos sin sombra.
- [ ] Farolillos en fachadas encendidos de noche.
