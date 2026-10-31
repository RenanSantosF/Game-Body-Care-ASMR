class_name Defs
extends RefCounted
## Dados do jogo: ferramentas, problemas e etapas de tratamento.

enum Mech { HOLD, RUB, CUT, PULL, TAP, SWEEP, PICK }

const MECH_HINT := {
	Mech.HOLD: "Segure!",
	Mech.RUB: "Esfregue por toda a área!",
	Mech.CUT: "Corte seguindo a linha!",
	Mech.PULL: "Puxe devagar!",
	Mech.TAP: "Arraste para CIMA colando o curativo!",
	Mech.SWEEP: "Passe por cima!",
	Mech.PICK: "Pegue um por um!",
}

# unlock = fase em que a ferramenta passa a aparecer
const TOOLS := {
	"pano":       {"name": "Pano úmido",  "unlock": 1,  "price": 0,   "desc": "Limpa sujeira e pus. Limpar antes facilita o tratamento!", "sharp": false},
	"algodao":    {"name": "Algodão",     "unlock": 1,  "price": 0,   "desc": "Antisséptico: limpa sangue e pus", "sharp": false},
	"agulha":     {"name": "Agulha",      "unlock": 1,  "price": 0,   "desc": "Fura espinhas e bolhas", "sharp": true},
	"espremedor": {"name": "Espremedor",  "unlock": 1,  "price": 0,   "desc": "Espreme o pus para fora", "sharp": false},
	"pinca":      {"name": "Pinça",       "unlock": 1,  "price": 0,   "desc": "Puxa farpas, pelos e bichos", "sharp": false},
	"curativo":   {"name": "Curativo",    "unlock": 2,  "price": 100, "desc": "Fecha feridas", "sharp": false},
	"lamina":     {"name": "Lâmina",      "unlock": 3,  "price": 180, "desc": "Raspa pelos crescidos", "sharp": true},
	"alicate":    {"name": "Alicate",     "unlock": 4,  "price": 250, "desc": "Corta unhas", "sharp": true},
	"bisturi":    {"name": "Bisturi",     "unlock": 5,  "price": 350, "desc": "Abre furúnculos e túneis de verme", "sharp": true},
	"raspador":   {"name": "Raspador",    "unlock": 6,  "price": 400, "desc": "Raspa calos, crostas e verrugas", "sharp": true},
	"pomada":     {"name": "Pomada",      "unlock": 7,  "price": 300, "desc": "Cicatriza e acalma a pele", "sharp": false},
	"lixa":       {"name": "Lixa",        "unlock": 8,  "price": 450, "desc": "Lixa unhas e calos", "sharp": false},
	"spray":      {"name": "Spray Gelo",  "unlock": 10, "price": 600, "desc": "Congela verrugas", "sharp": false},
}
const TOOL_ORDER := ["pano", "algodao", "agulha", "espremedor", "pinca", "curativo", "lamina", "alicate", "bisturi", "raspador", "pomada", "lixa", "spray"]

# where: pele (qualquer pele), dorso (costas da mão / peito do pé), dedo, unha, calo
# stages: [ferramenta, mecânica, quantidade]
#   HOLD = segundos | RUB = fração limpa (<=1) ou pixels (>1) | PULL = pixels | CUT/TAP/PICK/SWEEP = 1
const PROBLEMS := {
	"espinha":   {"name": "Espinha com pus", "tier": 1, "size": 0.07, "w": 6, "where": "pele",
		"stages": [["agulha", Mech.HOLD, 0.45], ["espremedor", Mech.HOLD, 1.3], ["algodao", Mech.RUB, 0.75]]},
	"bolha":     {"name": "Bolha d'água", "tier": 1, "size": 0.08, "w": 3, "where": "pele",
		"stages": [["agulha", Mech.HOLD, 0.4], ["algodao", Mech.RUB, 0.75], ["curativo", Mech.TAP, 1.0]]},
	"farpa":     {"name": "Farpa", "tier": 1, "size": 0.07, "w": 3, "where": "dedo",
		"stages": [["pinca", Mech.PULL, 230.0], ["algodao", Mech.RUB, 0.7]]},
	"sujeira":   {"name": "Sujeira grudada", "tier": 1, "size": 0.2, "w": 4, "where": "pele",
		"stages": [["pano", Mech.RUB, 0.8]]},
	"cravos":    {"name": "Cravos", "tier": 1, "size": 0.12, "w": 3, "where": "dorso",
		"stages": [["espremedor", Mech.PICK, 1.0], ["pano", Mech.RUB, 0.7]]},
	"pelos":     {"name": "Pelos crescidos", "tier": 1, "size": 0.24, "w": 4, "where": "dorso", "parts": ["mao", "pe", "costas"],
		"stages": [["lamina", Mech.SWEEP, 1.0]]},
	"pelo_encravado": {"name": "Pelo encravado", "tier": 2, "size": 0.06, "w": 3, "where": "pele",
		"stages": [["agulha", Mech.HOLD, 0.4], ["pinca", Mech.PULL, 300.0], ["algodao", Mech.RUB, 0.7]]},
	"carrapato": {"name": "Carrapato", "tier": 2, "size": 0.08, "w": 2, "where": "pele",
		"stages": [["pinca", Mech.PULL, 300.0], ["algodao", Mech.RUB, 0.7]]},
	"unha_suja": {"name": "Unha grande e suja", "tier": 2, "size": 0.1, "w": 4, "where": "unha",
		"stages": [["alicate", Mech.CUT, 1.0], ["pano", Mech.RUB, 0.75]]},
	"unha_pus":  {"name": "Unha inflamada com pus", "tier": 2, "size": 0.1, "w": 3, "where": "unha",
		"stages": [["agulha", Mech.HOLD, 0.45], ["espremedor", Mech.HOLD, 1.5], ["algodao", Mech.RUB, 0.75], ["curativo", Mech.TAP, 1.0]]},
	"crosta":    {"name": "Casca de ferida", "tier": 2, "size": 0.11, "w": 3, "where": "pele",
		"stages": [["algodao", Mech.RUB, 500.0], ["raspador", Mech.RUB, 0.75], ["pomada", Mech.RUB, 600.0]]},
	"calo":      {"name": "Calo grosso", "tier": 2, "size": 0.12, "w": 3, "where": "calo",
		"stages": [["raspador", Mech.RUB, 0.75], ["lixa", Mech.RUB, 700.0], ["pomada", Mech.RUB, 500.0]]},
	"fungo_unha": {"name": "Micose na unha", "tier": 2, "size": 0.1, "w": 3, "where": "unha",
		"stages": [["lixa", Mech.RUB, 0.75], ["pomada", Mech.RUB, 600.0]]},
	"furunculo": {"name": "Furúnculo gigante", "tier": 3, "size": 0.15, "w": 3, "where": "dorso",
		"stages": [["bisturi", Mech.CUT, 1.0], ["espremedor", Mech.HOLD, 2.4], ["algodao", Mech.RUB, 0.75], ["pomada", Mech.RUB, 450.0], ["curativo", Mech.TAP, 1.0]]},
	"verme":     {"name": "Verme debaixo da pele", "tier": 3, "size": 0.2, "w": 3, "where": "dorso",
		"stages": [["bisturi", Mech.CUT, 1.0], ["pinca", Mech.PULL, 650.0], ["algodao", Mech.RUB, 0.7], ["pomada", Mech.RUB, 450.0], ["curativo", Mech.TAP, 1.0]]},
	"larvas":    {"name": "Ferida com larvas", "tier": 3, "size": 0.19, "w": 2, "where": "dorso",
		"stages": [["pano", Mech.RUB, 0.7], ["pinca", Mech.PICK, 1.0], ["algodao", Mech.RUB, 0.7], ["pomada", Mech.RUB, 700.0], ["curativo", Mech.TAP, 1.0]]},
	"favo":      {"name": "Ferida cheia de buracos", "tier": 3, "size": 0.21, "w": 2, "where": "dorso",
		"stages": [["pano", Mech.RUB, 0.7], ["espremedor", Mech.PICK, 1.0], ["algodao", Mech.RUB, 600.0], ["pomada", Mech.RUB, 700.0], ["curativo", Mech.TAP, 1.0]]},
	"unha_encravada": {"name": "Unha encravada", "tier": 3, "size": 0.11, "w": 3, "where": "unha",
		"stages": [["alicate", Mech.CUT, 1.0], ["pinca", Mech.PULL, 260.0], ["algodao", Mech.RUB, 0.75], ["curativo", Mech.TAP, 1.0]]},
	"verruga":   {"name": "Verruga", "tier": 3, "size": 0.07, "w": 3, "where": "dedo",
		"stages": [["spray", Mech.HOLD, 1.3], ["raspador", Mech.RUB, 600.0], ["pomada", Mech.RUB, 400.0]]},
	# --- novos, bem nojentos
	"abscesso":  {"name": "Abscesso de pus verde", "tier": 3, "size": 0.17, "w": 3, "where": "dorso",
		"stages": [["bisturi", Mech.CUT, 1.0], ["espremedor", Mech.HOLD, 2.8], ["algodao", Mech.RUB, 0.75], ["pomada", Mech.RUB, 450.0], ["curativo", Mech.TAP, 1.0]]},
	"cisto":     {"name": "Cisto sebáceo", "tier": 2, "size": 0.1, "w": 3, "where": "pele",
		"stages": [["agulha", Mech.HOLD, 0.5], ["espremedor", Mech.HOLD, 2.0], ["algodao", Mech.RUB, 0.75]]},
	"ralado":    {"name": "Ralado infeccionado", "tier": 2, "size": 0.16, "w": 3, "where": "dorso",
		"stages": [["pinca", Mech.PICK, 1.0], ["pano", Mech.RUB, 0.75], ["pomada", Mech.RUB, 600.0], ["curativo", Mech.TAP, 1.0]]},
	"bicho_pe":  {"name": "Bicho-de-pé", "tier": 3, "size": 0.07, "w": 3, "where": "calo",
		"stages": [["agulha", Mech.HOLD, 0.6], ["pinca", Mech.PULL, 260.0], ["algodao", Mech.RUB, 0.7], ["curativo", Mech.TAP, 1.0]]},
	"espinhos":  {"name": "Espinhos de cacto", "tier": 2, "size": 0.13, "w": 3, "where": "pele",
		"stages": [["pinca", Mech.PICK, 1.0], ["algodao", Mech.RUB, 0.7]]},
	"unha_roxa": {"name": "Unha roxa (sangue preso)", "tier": 2, "size": 0.1, "w": 2, "where": "unha",
		"stages": [["agulha", Mech.HOLD, 1.0], ["algodao", Mech.RUB, 0.75]]},
	# --- maiores e mais feios (v0.9) + partes novas do corpo
	"carbunculo": {"name": "Carbúnculo (furúnculo com várias cabeças)", "tier": 3, "size": 0.24, "w": 3, "where": "dorso",
		"stages": [["bisturi", Mech.CUT, 1.0], ["espremedor", Mech.HOLD, 3.4], ["algodao", Mech.RUB, 0.75], ["pomada", Mech.RUB, 450.0], ["curativo", Mech.TAP, 1.0]]},
	"acne_costas": {"name": "Acne inflamada", "tier": 2, "size": 0.22, "w": 4, "where": "dorso", "parts": ["costas", "rosto", "mao"],
		"stages": [["espremedor", Mech.PICK, 1.0], ["algodao", Mech.RUB, 0.75]]},
	"queimadura": {"name": "Queimadura com bolhas", "tier": 2, "size": 0.2, "w": 3, "where": "dorso",
		"stages": [["agulha", Mech.HOLD, 0.9], ["pinca", Mech.PICK, 1.0], ["pomada", Mech.RUB, 600.0], ["curativo", Mech.TAP, 1.0]]},
	"pontos":    {"name": "Pontos infeccionados", "tier": 2, "size": 0.17, "w": 3, "where": "dorso",
		"stages": [["pinca", Mech.PICK, 1.0], ["algodao", Mech.RUB, 0.75], ["pomada", Mech.RUB, 450.0], ["curativo", Mech.TAP, 1.0]]},
	"piolhos":   {"name": "Piolhos e lêndeas", "tier": 2, "size": 0.22, "w": 5, "where": "cabelo",
		"stages": [["pinca", Mech.PICK, 1.0], ["pano", Mech.RUB, 0.75]]},
	"caspa":     {"name": "Caspa grossa (seborreia)", "tier": 1, "size": 0.2, "w": 5, "where": "cabelo",
		"stages": [["pano", Mech.RUB, 0.8], ["algodao", Mech.RUB, 400.0]]},
	"barba":     {"name": "Barba enorme", "tier": 1, "size": 0.3, "w": 5, "where": "barba",
		"stages": [["lamina", Mech.SWEEP, 1.0]]},
	# criado quando o jogador machuca o paciente
	"machucado": {"name": "Machucado", "tier": 99, "size": 0.06, "w": 0, "where": "pele",
		"stages": [["algodao", Mech.RUB, 0.7], ["curativo", Mech.TAP, 1.0]]},
}

## pacientes chefe (a cada 5 fases)
const BOSSES := ["Zé do Pântano", "Dona Gosma", "Barão do Pus", "Tio Lodo", "Madame Craca", "Rei do Chulé", "Vovó Verruga", "Capitão Casca"]

const NAMES := ["Seu Juca", "Dona Cida", "Tio Zé", "Bruna", "Kevin", "Dona Neide", "Marcão",
	"Lu", "Pedrinho", "Vó Dalva", "Rafa", "Tia Sônia", "Jéssica", "Seu Arnaldo", "Diego",
	"Valdirene", "Cleitinho", "Dona Zuleide", "Thiago", "Seu Bené", "Paty", "Gilmar"]

const PART_NAMES := {"mao": "Mão", "pe": "Pé", "costas": "Costas", "rosto": "Rosto", "cabeca": "Cabeça"}

const THANKS := ["Muito obrigado, doutor!", "Nem acredito, tô novo!", "Que alívio!!",
	"Vou voltar sempre!", "Minha mãe não vai me reconhecer!", "Brilhando igual pão de queijo!",
	"Pode cobrar o dobro!", "Melhor clínica da cidade!"]

const OUCH := ["AAAI!", "Tá doendo!!", "Cuidado, doutor!", "Essa não é a ferramenta certa!",
	"Buáaa!", "Vou chamar meu advogado!", "Ai ai ai!", "Para, para!", "Isso dói!!"]
const OUCH_FAST := ["Devagar!!", "Calma, doutor!", "Tá arrancando tudo!"]
const OUCH_DIRTY := ["Limpa antes, tá ardendo!", "Tá tudo sujo, dói mais!"]
const RELIEF := ["Aaah, melhorou!", "Que alívio...", "Isso, doutor!", "Nossa, saiu tudo!"]

const SKINS := [Color("f6d2b5"), Color("efc09c"), Color("dca27c"), Color("c08560"), Color("9a6543"), Color("74472d")]

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
