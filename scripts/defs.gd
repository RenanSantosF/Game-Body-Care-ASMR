class_name Defs
extends RefCounted
## Dados do jogo: ferramentas, problemas e suas etapas de tratamento.

enum Mech { HOLD, RUB, CUT, PULL, TAP, SWEEP, PICK }

const MECH_HINT := {
	Mech.HOLD: "Segure!",
	Mech.RUB: "Esfregue!",
	Mech.CUT: "Corte arrastando!",
	Mech.PULL: "Puxe devagar!",
	Mech.TAP: "Toque!",
	Mech.SWEEP: "Passe por cima!",
	Mech.PICK: "Pegue um por um!",
}

# unlock = fase em que a ferramenta pode aparecer / ser comprada
const TOOLS := {
	"algodao":    {"name": "Algodão",    "unlock": 1,  "price": 0,   "desc": "Limpa pus e sangue"},
	"espremedor": {"name": "Espremedor", "unlock": 1,  "price": 0,   "desc": "Espreme espinhas"},
	"pinca":      {"name": "Pinça",      "unlock": 1,  "price": 0,   "desc": "Puxa farpas e bichos"},
	"escova":     {"name": "Escova",     "unlock": 2,  "price": 120, "desc": "Esfrega sujeira e lama"},
	"espatula":   {"name": "Espátula",   "unlock": 3,  "price": 200, "desc": "Raspa cravos e crostas"},
	"lamina":     {"name": "Lâmina",     "unlock": 4,  "price": 300, "desc": "Raspa pelos crescidos"},
	"bisturi":    {"name": "Bisturi",    "unlock": 6,  "price": 450, "desc": "Abre capas de pus"},
	"curativo":   {"name": "Curativo",   "unlock": 9,  "price": 250, "desc": "Fecha feridas"},
	"spray":      {"name": "Spray Gelo", "unlock": 10, "price": 600, "desc": "Congela verrugas e bichos"},
	"pente":      {"name": "Pente Fino", "unlock": 12, "price": 500, "desc": "Tira pulgas"},
}
const TOOL_ORDER := ["algodao", "espremedor", "pinca", "escova", "espatula", "lamina", "bisturi", "curativo", "spray", "pente"]

# stages: [ferramenta, mecânica, quantidade]
#   HOLD = segundos | RUB/CUT/PULL = pixels arrastados | SWEEP/PICK/TAP = por item
const PROBLEMS := {
	# --- tier 1: simples ---
	"espinha":   {"name": "Espinha", "tier": 1, "size": 0.12, "w": 5,
		"stages": [["espremedor", Mech.HOLD, 1.1], ["algodao", Mech.RUB, 650.0]]},
	"farpa":     {"name": "Farpa", "tier": 1, "size": 0.12, "w": 3,
		"stages": [["pinca", Mech.PULL, 240.0]]},
	"sujeira":   {"name": "Sujeira", "tier": 1, "size": 0.16, "w": 4,
		"stages": [["escova", Mech.RUB, 1000.0]]},
	"cravo":     {"name": "Cravo", "tier": 1, "size": 0.09, "w": 4,
		"stages": [["espatula", Mech.RUB, 450.0]]},
	"chiclete":  {"name": "Chiclete grudado", "tier": 1, "size": 0.14, "w": 2,
		"stages": [["espatula", Mech.RUB, 700.0]]},
	# --- tier 2: nojento ---
	"capa_pus":  {"name": "Capa de pus", "tier": 2, "size": 0.15, "w": 4,
		"stages": [["bisturi", Mech.CUT, 220.0], ["espremedor", Mech.HOLD, 1.6], ["algodao", Mech.RUB, 800.0]]},
	"espinhas":  {"name": "Ninho de espinhas", "tier": 2, "size": 0.22, "w": 3,
		"stages": [["espremedor", Mech.PICK, 1.0], ["algodao", Mech.RUB, 900.0]]},
	"cravos":    {"name": "Poros entupidos", "tier": 2, "size": 0.22, "w": 3,
		"stages": [["espatula", Mech.SWEEP, 1.0]]},
	"lama":      {"name": "Lama grossa", "tier": 2, "size": 0.18, "w": 3,
		"stages": [["escova", Mech.RUB, 1300.0], ["algodao", Mech.RUB, 600.0]]},
	"pelos":     {"name": "Pelos crescidos", "tier": 2, "size": 0.25, "w": 4,
		"stages": [["lamina", Mech.SWEEP, 1.0]]},
	"pelo_encravado": {"name": "Pelo encravado", "tier": 2, "size": 0.1, "w": 3,
		"stages": [["pinca", Mech.PULL, 320.0], ["algodao", Mech.RUB, 400.0]]},
	"crosta":    {"name": "Crosta seca", "tier": 2, "size": 0.15, "w": 3,
		"stages": [["espatula", Mech.RUB, 850.0], ["algodao", Mech.RUB, 450.0]]},
	"carrapato": {"name": "Carrapato", "tier": 2, "size": 0.12, "w": 3,
		"stages": [["pinca", Mech.PULL, 300.0], ["algodao", Mech.RUB, 400.0]]},
	# --- tier 3: muito nojento ---
	"furunculo": {"name": "Furúnculo gigante", "tier": 3, "size": 0.23, "w": 3,
		"stages": [["bisturi", Mech.CUT, 260.0], ["espremedor", Mech.HOLD, 2.6], ["algodao", Mech.RUB, 1000.0], ["curativo", Mech.TAP, 1.0]]},
	"verme":     {"name": "Verme na pele", "tier": 3, "size": 0.12, "w": 3,
		"stages": [["pinca", Mech.PULL, 650.0], ["algodao", Mech.RUB, 500.0], ["curativo", Mech.TAP, 1.0]]},
	"berne":     {"name": "Berne", "tier": 3, "size": 0.14, "w": 2,
		"stages": [["espremedor", Mech.HOLD, 1.6], ["pinca", Mech.PULL, 320.0], ["curativo", Mech.TAP, 1.0]]},
	"larvas":    {"name": "Ferida com larvas", "tier": 3, "size": 0.22, "w": 2,
		"stages": [["pinca", Mech.PICK, 1.0], ["algodao", Mech.RUB, 900.0], ["curativo", Mech.TAP, 1.0]]},
	"verruga":   {"name": "Verruga", "tier": 3, "size": 0.12, "w": 3,
		"stages": [["spray", Mech.HOLD, 1.4], ["espatula", Mech.RUB, 550.0]]},
	"sanguessuga": {"name": "Sanguessuga", "tier": 3, "size": 0.17, "w": 2,
		"stages": [["spray", Mech.HOLD, 1.3], ["pinca", Mech.PULL, 330.0], ["algodao", Mech.RUB, 450.0]]},
	"pulgas":    {"name": "Pulgas", "tier": 3, "size": 0.22, "w": 2,
		"stages": [["pente", Mech.SWEEP, 1.0]]},
}

const NAMES := ["Seu Juca", "Dona Cida", "Tio Zé", "Bruna", "Kevin", "Dona Neide", "Marcão",
	"Lu", "Pedrinho", "Vó Dalva", "Rafa", "Tia Sônia", "Jéssica", "Seu Arnaldo", "Diego",
	"Valdirene", "Cleitinho", "Dona Zuleide", "Thiago", "Seu Bené", "Paty", "Gilmar"]

const PART_NAMES := {"rosto": "Rosto", "braco": "Braço", "costas": "Costas", "pe": "Pé"}

const THANKS := ["Muito obrigado, doutor!", "Nem acredito, tô lindo!", "Que alívio!!",
	"Vou voltar sempre!", "Minha mãe não vai me reconhecer!", "Brilhando igual pão de queijo!",
	"Pode cobrar o dobro!", "Melhor clínica da cidade!"]

const SKINS := [Color("f6d2b5"), Color("eab894"), Color("d49b72"), Color("b97a52"), Color("8d5a3b"), Color("6b4129")]
const HAIRS := [Color("2b1d14"), Color("5a3a22"), Color("a0522d"), Color("e3c27a"), Color("1a1a1a"), Color("8a8a8a"), Color("c94f2e")]
const SHIRTS := [Color("4fb3ff"), Color("ff7eb6"), Color("7ed957"), Color("ffcf4f"), Color("9b7bff"), Color("ff8f4f")]

static func stage_count(id: String) -> int:
	return PROBLEMS[id]["stages"].size()

static func tools_of(id: String) -> Array:
	var out := []
	for s in PROBLEMS[id]["stages"]:
		if not out.has(s[0]):
			out.append(s[0])
	return out

static func problem_available(id: String, level: int) -> bool:
	for t in tools_of(id):
		if TOOLS[t]["unlock"] > level:
			return false
	return true

static func upgrade_price(tool_id: String, cur_lvl: int) -> int:
	var base: int = max(100, TOOLS[tool_id]["price"])
	return int(base * 0.8 * cur_lvl + 80)
