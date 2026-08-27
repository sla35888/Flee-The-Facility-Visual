--[[
	LocalScript: UnifiedHammerAndAnchorSystem.client.luau
	Localização: StarterPlayer -> StarterPlayerScripts
	
	Padrão: R6
	Funcionalidades Integradas:
	1. Tremor de câmera (<= 50 studs) e Blur (<= 30 studs) baseados em modelos com "Hammer",
	   calculados dinamicamente com base no foco atual da câmera (suporte a modo Espectador).
	2. Sistema de Área: Se o LocalPlayer está com Torso.Anchored = true, aplica Highlight Ciano
	   (entrada/saída em 0.5s) para todos no raio de 125 studs (exceto portadores de Hammer).
	3. Reação a Perigo: Se o Hammer estiver a <= 30 studs de um personagem ancorado, o Highlight vira Vermelho.
	   Ao se afastar, faz transição de Vermelho para Ciano em 1.0s.
	4. Animação Verde ao Desancorar: Quando um personagem desancora, o Highlight transiciona para
	   Verde em 0.5s, permanece Verde por 1.5s e desativa.
	5. Monitoramento Reativo de Screens/Computadores no Workspace (Correção de Re-Highlight Vermelho).
	6. Efeitos de PlatformStand (Desmaio) com distorção sonora em outros áudios.
	7. SISTEMA DE SURVIVOR CELL (COM SUPORTE A ESPECTADOR): Monitora a UI do jogador focado
	   e aplica efeitos progressivos de Ciano, Desfoco, Tremor e NÉVOA CIANO CRÍTICA (decaimento 1 min).
	8. Áudio de Hammer em 1ª Pessoa sem visibilidade (<= 100 studs, cooldown 60s, id: 137676151435354).
	9. SISTEMA DETECTOR: Monitora sons em modelos "Detector". Jogadores a <= 15 studs recebem Highlight Vermelho por 1.5s.
	10. SISTEMA DE POÇAS DE SANGUE (PLATFORMSTAND): Poças inteligentes que expandem até 6 studs na mesma posição e respeitam Torso.Anchored.
	11. REMOÇÃO AUTOMÁTICA DE BILLBOARDS: Destrói automaticamente os BillboardGuis dentro de FreezePods (PodRoof) e Computers ao surgirem.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- CONFIGURAÇÕES E CONSTANTES
--------------------------------------------------------------------------------
local NOME_HAMMER = "Hammer"
local NOME_DETECTOR = "Detector"
local DISTANCIA_MAX_TREMOR = 50
local DISTANCIA_MAX_DESFOCO = 30
local RAIO_AREA_ANCORA = 125
local RAIO_DETECTOR = 15
local BLUR_MAXIMO = 12
local AUDIO_PLATFORMSTAND_ID = "rbxassetid://9069161602"
local AUDIO_HAMMER_OUT_OF_FOV_ID = "rbxassetid://137676151435354"
local NOME_EFEITO_AUDIO_DESMAIO = "FaintingAudioDistortion"

local RENDER_ID = "UnifiedR6HammerAndAnchorSystem"

-- Controle de Cooldown do Áudio de FoV do Hammer
local ultimoTempoAudioHammerFOV = 0
local COOLDOWN_AUDIO_HAMMER_FOV = 60

-- Definição de Cores de Referência
local COR_CIANO_OUTLINE = Color3.fromRGB(0, 255, 255)
local COR_CIANO_FILL    = Color3.fromRGB(0, 255, 255)

local COR_VERMELHO_OUTLINE = Color3.fromRGB(255, 0, 0)
local COR_VERMELHO_FILL    = Color3.fromRGB(255, 0, 0)

local COR_VERDE_OUTLINE = Color3.fromRGB(0, 255, 0)
local COR_VERDE_FILL    = Color3.fromRGB(0, 255, 0)

local COR_REF_VERMELHO  = Color3.fromRGB(255, 0, 0)
local COR_REF_VERDE     = Color3.fromRGB(0, 255, 0)
local COR_REF_VERDE_CLARO = Color3.fromRGB(144, 238, 144)

--------------------------------------------------------------------------------
-- EFEITOS NO LIGHTING
--------------------------------------------------------------------------------
local blurEffect = Lighting:FindFirstChild("HammerUnifiedBlur") :: BlurEffect
if not blurEffect then
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "HammerUnifiedBlur"
	blurEffect.Size = 0
	blurEffect.Enabled = true
	blurEffect.Parent = Lighting
end

local platformBlurEffect = Lighting:FindFirstChild("PlatformStandBlur") :: BlurEffect
if not platformBlurEffect then
	platformBlurEffect = Instance.new("BlurEffect")
	platformBlurEffect.Name = "PlatformStandBlur"
	platformBlurEffect.Size = 0
	platformBlurEffect.Enabled = true
	platformBlurEffect.Parent = Lighting
end

local platformBlindness = Lighting:FindFirstChild("PlatformStandBlindness") :: ColorCorrectionEffect
if not platformBlindness then
	platformBlindness = Instance.new("ColorCorrectionEffect")
	platformBlindness.Name = "PlatformStandBlindness"
	platformBlindness.Brightness = 0
	platformBlindness.Enabled = true
	platformBlindness.Parent = Lighting
end

local survivorCellBlur = Lighting:FindFirstChild("SurvivorCellBlur") :: BlurEffect
if not survivorCellBlur then
	survivorCellBlur = Instance.new("BlurEffect")
	survivorCellBlur.Name = "SurvivorCellBlur"
	survivorCellBlur.Size = 0
	survivorCellBlur.Enabled = true
	survivorCellBlur.Parent = Lighting
end

local survivorCellCC = Lighting:FindFirstChild("SurvivorCellCC") :: ColorCorrectionEffect
if not survivorCellCC then
	survivorCellCC = Instance.new("ColorCorrectionEffect")
	survivorCellCC.Name = "SurvivorCellCC"
	survivorCellCC.TintColor = Color3.fromRGB(255, 255, 255)
	survivorCellCC.Enabled = true
	survivorCellCC.Parent = Lighting
end

-- Névoa Ciano Customizada
local survivorCellAtmosphere: Atmosphere? = nil

local function obterOuCriarNevoaCritica(): Atmosphere
	if not survivorCellAtmosphere or not survivorCellAtmosphere.Parent then
		survivorCellAtmosphere = Instance.new("Atmosphere")
		survivorCellAtmosphere.Name = "SurvivorCellFog_Custom"
		survivorCellAtmosphere.Color = Color3.fromRGB(0, 255, 255)
		survivorCellAtmosphere.Decay = Color3.fromRGB(0, 180, 220)
		survivorCellAtmosphere.Density = 0
		survivorCellAtmosphere.Offset = 0
		survivorCellAtmosphere.Haze = 0
		survivorCellAtmosphere.Glare = 0
	end
	return survivorCellAtmosphere :: Atmosphere
end

local function removerNevoaCritica()
	if survivorCellAtmosphere then
		survivorCellAtmosphere.Parent = nil
	end
end

--------------------------------------------------------------------------------
-- ESTRUTURA DE DADOS
--------------------------------------------------------------------------------
type DadosPersonagem = {
	Modelo: Model,
	Torso: BasePart,
	Highlight: Highlight,
	NoRaioArea: boolean,
	EstadoAncoradoLocal: boolean,
	EmPerigoHammer: boolean,
	EmAnimacaoVerde: boolean,
	EmAnimacaoDetector: boolean,
	TweenAtual: Tween?,
	ThreadVerde: thread?,
	ThreadDetector: thread?
}

type DadosComputador = {
	ModeloComputer: Model,
	Highlight: Highlight,
	EstadoCor: "Nenhum" | "Vermelho" | "Verde",
	ThreadExpiracao: thread?,
	TweenAtual: Tween?
}

local personagensRegistrados: {[Model]: DadosPersonagem} = {}
local computadoresRegistrados: {[Model]: DadosComputador} = {}
local conexoesScreens: {[Instance]: RBXScriptConnection} = {}
local conexoesPlatformStand: {[Humanoid]: RBXScriptConnection} = {}
local conexoesDetectores: {[Sound]: RBXScriptConnection} = {}
local conexoesAnchoredLocal: RBXScriptConnection? = nil

local emEstadoDesmaioSonoro = false
local filtrosAudioAtivos: {[EqualizerSoundEffect]: Tween} = {}
local conexaoNovoAudioWorkspace: RBXScriptConnection? = nil
local conexaoNovoAudioSoundService: RBXScriptConnection? = nil

local intensidadeTremorAtual = 0
local intensidadeBlurAtual = 0
local tremorSurvivorCellAtual = 0
local tempoAcumulado = 0

-- Variáveis do Decaimento do SurvivorCell (1 minuto após desancorar)
local fatorSurvivorCellDecay = 1.0
local foiAncoradoAnteriormente = false
local jogadorAncoradoAnterior: Player? = nil

local tweenPlatformBlur: Tween? = nil
local tweenPlatformBlindness: Tween? = nil
local threadsGeracaoSangue: {[Humanoid]: thread} = {}

--------------------------------------------------------------------------------
-- REMOÇÃO DE BILLBOARD (FREEZEPOD & COMPUTERS)
--------------------------------------------------------------------------------
local function limparBillboardFreezePod(instancia: Instance)
	if not instancia:IsA("Model") then return end
	if string.sub(instancia.Name, 1, 9) == "FreezePod" then
		local podRoof = instancia:FindFirstChild("PodRoof")
		if podRoof then
			local billboard = podRoof:FindFirstChildOfClass("BillboardGui")
			if billboard then
				billboard:Destroy()
			end
		end
		-- Escuta caso o PodRoof ou Billboard seja adicionado posteriormente
		instancia.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BillboardGui") and descendant.Parent and descendant.Parent.Name == "PodRoof" then
				descendant:Destroy()
			end
		end)
	end
end

local function limparBillboardComputer(instancia: Instance)
	if not instancia:IsA("Model") then return end
	if string.sub(instancia.Name, 1, 8) == "Computer" then
		for _, desc in instancia:GetDescendants() do
			if desc:IsA("BillboardGui") then
				desc:Destroy()
			end
		end
		instancia.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BillboardGui") then
				descendant:Destroy()
			end
		end)
	end
end

-- Varredura Inicial e Monitoramento Ativo (Sem loops contínuos)
for _, child in Workspace:GetChildren() do
	limparBillboardFreezePod(child)
	limparBillboardComputer(child)
end

Workspace.ChildAdded:Connect(function(child)
	limparBillboardFreezePod(child)
	limparBillboardComputer(child)
end)

--------------------------------------------------------------------------------
-- MATEMÁTICA E UTILITÁRIOS DE COR
--------------------------------------------------------------------------------
local function obterDistanciaCor(c1: Color3, c2: Color3): number
	local dr = c1.R - c2.R
	local dg = c1.G - c2.G
	local db = c1.B - c2.B
	return math.sqrt(dr * dr + dg * dg + db * db)
end

local function extrairCorObjeto(objeto: Instance): Color3?
	if objeto:IsA("BasePart") then
		return objeto.Color
	elseif objeto:IsA("ImageLabel") or objeto:IsA("ImageButton") then
		return objeto.ImageColor3
	elseif objeto:IsA("Frame") or objeto:IsA("TextLabel") or objeto:IsA("TextButton") then
		return objeto.BackgroundColor3
	elseif objeto:IsA("Light") then
		return objeto.Color
	end
	return nil
end

local function obterNomePropriedadeCor(objeto: Instance): string?
	if objeto:IsA("BasePart") then
		return "Color"
	elseif objeto:IsA("ImageLabel") or objeto:IsA("ImageButton") then
		return "ImageColor3"
	elseif objeto:IsA("Frame") or objeto:IsA("TextLabel") or objeto:IsA("TextButton") then
		return "BackgroundColor3"
	elseif objeto:IsA("Light") then
		return "Color"
	end
	return nil
end

--------------------------------------------------------------------------------
-- GERENCIADOR DE INJEÇÃO SONORA DE DESMAIO
--------------------------------------------------------------------------------
local function injetarFiltroDesmaioEmAudio(sound: Sound)
	if not sound or not sound:IsA("Sound") or not sound.Parent then return end
	if sound.Name == "PlatformStandSound" or sound.SoundId == AUDIO_PLATFORMSTAND_ID then return end

	local filtroExistente = sound:FindFirstChild(NOME_EFEITO_AUDIO_DESMAIO) :: EqualizerSoundEffect?
	if not filtroExistente then
		filtroExistente = Instance.new("EqualizerSoundEffect")
		filtroExistente.Name = NOME_EFEITO_AUDIO_DESMAIO
		filtroExistente.Priority = 10
		filtroExistente.Parent = sound
	end

	filtroExistente.HighGain = -35
	filtroExistente.MidGain = -15
	filtroExistente.LowGain = 5
	filtroExistente.Enabled = true

	local infoTween = TweenInfo.new(25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local tweenFiltro = TweenService:Create(filtroExistente, infoTween, {
		HighGain = 0,
		MidGain = 0,
		LowGain = 0
	})

	filtrosAudioAtivos[filtroExistente] = tweenFiltro

	tweenFiltro.Completed:Connect(function()
		if filtrosAudioAtivos[filtroExistente] then
			filtrosAudioAtivos[filtroExistente] = nil
		end
		if filtroExistente and filtroExistente.Parent then
			filtroExistente:Destroy()
		end
	end)

	tweenFiltro:Play()
end

local function aplicarDistorcaoSonoraGlobal()
	emEstadoDesmaioSonoro = true

	local todosOsObjetos = Workspace:GetDescendants()
	for _, obj in SoundService:GetDescendants() do
		table.insert(todosOsObjetos, obj)
	end

	for _, instancia in todosOsObjetos do
		if instancia:IsA("Sound") then
			injetarFiltroDesmaioEmAudio(instancia)
		end
	end

	if not conexaoNovoAudioWorkspace then
		conexaoNovoAudioWorkspace = Workspace.DescendantAdded:Connect(function(descendant)
			if emEstadoDesmaioSonoro and descendant:IsA("Sound") then
				injetarFiltroDesmaioEmAudio(descendant)
			end
		end)
	end

	if not conexaoNovoAudioSoundService then
		conexaoNovoAudioSoundService = SoundService.DescendantAdded:Connect(function(descendant)
			if emEstadoDesmaioSonoro and descendant:IsA("Sound") then
				injetarFiltroDesmaioEmAudio(descendant)
			end
		end)
	end
end

local function removerDistorcaoSonoraGlobal()
	emEstadoDesmaioSonoro = false

	if conexaoNovoAudioWorkspace then
		conexaoNovoAudioWorkspace:Disconnect()
		conexaoNovoAudioWorkspace = nil
	end

	if conexaoNovoAudioSoundService then
		conexaoNovoAudioSoundService:Disconnect()
		conexaoNovoAudioSoundService = nil
	end

	for filtro, tween in pairs(filtrosAudioAtivos) do
		if tween then tween:Cancel() end
		if filtro and filtro.Parent then
			filtro:Destroy()
		end
	end
	table.clear(filtrosAudioAtivos)
end

--------------------------------------------------------------------------------
-- CANCELAMENTO DE EFEITOS DE DESMAIO
--------------------------------------------------------------------------------
local function cancelarEfeitosDesmaioLocal()
	if tweenPlatformBlur then
		tweenPlatformBlur:Cancel()
		tweenPlatformBlur = nil
	end
	if tweenPlatformBlindness then
		tweenPlatformBlindness:Cancel()
		tweenPlatformBlindness = nil
	end

	platformBlurEffect.Size = 0
	platformBlindness.Brightness = 0

	removerDistorcaoSonoraGlobal()
end

--------------------------------------------------------------------------------
-- GERADOR DE SANGUE (PLATFORMSTAND)
--------------------------------------------------------------------------------
local function criarOuExpandirSangueNoChao(posicaoOrigem: Vector3)
	local meiasPocas = Workspace:FindPartsInRegion3WithWhiteList(
		Region3.new(posicaoOrigem - Vector3.new(4, 4, 4), posicaoOrigem + Vector3.new(4, 4, 4)),
		{Workspace},
		100
	)

	local pocaProxima: Part? = nil
	for _, part in meiasPocas do
		if part.Name == "BloodPuddle" and part:IsA("Part") then
			local dist = (Vector3.new(part.Position.X, 0, part.Position.Z) - Vector3.new(posicaoOrigem.X, 0, posicaoOrigem.Z)).Magnitude
			if dist <= 4 then
				pocaProxima = part
				break
			end
		end
	end

	if pocaProxima then
		local tamanhoAtual = pocaProxima.Size.X
		if tamanhoAtual < 6 then
			local novoTamanho = math.min(6, tamanhoAtual + 0.6)
			local infoExpansao = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tweenExpande = TweenService:Create(pocaProxima, infoExpansao, {
				Size = Vector3.new(novoTamanho, 0.02, novoTamanho)
			})
			tweenExpande:Play()
		end
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local objetosExcluidos: {Instance} = {}
	for _, child in Workspace:GetChildren() do
		if (child:IsA("Model") and child:FindFirstChildOfClass("Humanoid")) or child.Name == "BloodPuddle" then
			table.insert(objetosExcluidos, child)
		end
	end
	raycastParams.FilterDescendantsInstances = objetosExcluidos

	local raycastResult = Workspace:Raycast(posicaoOrigem + Vector3.new(0, 2, 0), Vector3.new(0, -20, 0), raycastParams)
	if not raycastResult then return end

	local posChao = raycastResult.Position

	local sangue = Instance.new("Part")
	sangue.Name = "BloodPuddle"
	sangue.Anchored = true
	sangue.CanCollide = false
	sangue.CastShadow = false
	sangue.Material = Enum.Material.SmoothPlastic

	local tamanhoInicial = math.random() * (2 - 1) + 1
	sangue.Size = Vector3.new(tamanhoInicial, 0.02, tamanhoInicial)
	sangue.CFrame = CFrame.new(posChao + Vector3.new(0, 0.01, 0)) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0)

	local tomEscuro = math.random() * 0.4
	sangue.Color = Color3.new(0.4 + (math.random() * 0.6) - tomEscuro, 0, 0)
	sangue.Transparency = math.random() * (0.25 - 0.15) + 0.15

	sangue.Parent = Workspace

	local tamanhoFinal = math.random() * (5 - 3) + 3
	local infoCrescimento = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenCrescer = TweenService:Create(sangue, infoCrescimento, {
		Size = Vector3.new(tamanhoFinal, 0.02, tamanhoFinal)
	})
	tweenCrescer:Play()

	task.delay(15, function()
		if sangue and sangue.Parent then
			local infoSumiu = TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
			local tweenSumiu = TweenService:Create(sangue, infoSumiu, { Transparency = 1 })
			tweenSumiu:Play()
			tweenSumiu.Completed:Connect(function()
				if sangue and sangue.Parent then
					sangue:Destroy()
				end
			end)
		end
	end)
end

local function iniciarGeracaoSangue(humanoid: Humanoid)
	if threadsGeracaoSangue[humanoid] then return end

	threadsGeracaoSangue[humanoid] = task.spawn(function()
		while humanoid and humanoid.Parent and humanoid.PlatformStand do
			local char = humanoid.Parent
			local torso = char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
			
			if torso and torso:IsA("BasePart") and not torso.Anchored then
				criarOuExpandirSangueNoChao(torso.Position)
			else
				break
			end
			
			local intervalo = math.random() * (1.25 - 0.5) + 0.5
			task.wait(intervalo)
		end
		threadsGeracaoSangue[humanoid] = nil
	end)
end

--------------------------------------------------------------------------------
-- PLATFORMSTAND
--------------------------------------------------------------------------------
local function dispararEfeitosPlatformStand(humanoid: Humanoid)
	local char = humanoid.Parent
	if not char or not char:IsA("Model") then return end
	local torso = char:FindFirstChild("Torso") :: BasePart?
	if not torso then return end

	iniciarGeracaoSangue(humanoid)

	if torso.Anchored then return end

	local ehJogadorLocal = (char == LocalPlayer.Character)

	if ehJogadorLocal then
		cancelarEfeitosDesmaioLocal()

		platformBlurEffect.Size = 56
		local infoBlur = TweenInfo.new(25, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		tweenPlatformBlur = TweenService:Create(platformBlurEffect, infoBlur, {Size = 0})
		tweenPlatformBlur:Play()

		platformBlindness.Brightness = -1
		local infoBlindness = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tweenPlatformBlindness = TweenService:Create(platformBlindness, infoBlindness, {Brightness = 0})
		tweenPlatformBlindness:Play()

		aplicarDistorcaoSonoraGlobal()

		local sound = Instance.new("Sound")
		sound.Name = "PlatformStandSound"
		sound.SoundId = AUDIO_PLATFORMSTAND_ID
		sound.Looped = false
		sound.Volume = 0.45
		sound.Parent = SoundService

		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end
end

local function monitorarHumanoidPlatformStand(humanoid: Humanoid)
	if conexoesPlatformStand[humanoid] then return end

	conexoesPlatformStand[humanoid] = humanoid:GetPropertyChangedSignal("PlatformStand"):Connect(function()
		if humanoid.PlatformStand then
			dispararEfeitosPlatformStand(humanoid)
		end
	end)

	if humanoid.PlatformStand then
		dispararEfeitosPlatformStand(humanoid)
	end

	local char = humanoid.Parent
	if char and char == LocalPlayer.Character then
		local torso = char:FindFirstChild("Torso") :: BasePart?
		if torso and not conexoesAnchoredLocal then
			conexoesAnchoredLocal = torso:GetPropertyChangedSignal("Anchored"):Connect(function()
				if torso.Anchored then
					cancelarEfeitosDesmaioLocal()
				end
			end)
		end
	end
end

local function desconectarHumanoidPlatformStand(humanoid: Humanoid)
	if conexoesPlatformStand[humanoid] then
		conexoesPlatformStand[humanoid]:Disconnect()
		conexoesPlatformStand[humanoid] = nil
	end

	if threadsGeracaoSangue[humanoid] then
		task.cancel(threadsGeracaoSangue[humanoid])
		threadsGeracaoSangue[humanoid] = nil
	end

	local char = humanoid.Parent
	if char and char == LocalPlayer.Character and conexoesAnchoredLocal then
		conexoesAnchoredLocal:Disconnect()
		conexoesAnchoredLocal = nil
	end
end

--------------------------------------------------------------------------------
-- HAMMER CHECKS
--------------------------------------------------------------------------------
local function possuiHammer(modelo: Model): boolean
	if not modelo or not modelo:IsA("Model") then return false end
	if not modelo:IsDescendantOf(Workspace) then return false end

	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	if modelo:FindFirstChild(NOME_HAMMER) then
		return true
	end

	local player = Players:GetPlayerFromCharacter(modelo)
	if player then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack and backpack:FindFirstChild(NOME_HAMMER) then
			return true
		end
	end

	return false
end

local function obterPosicoesHammersAtivos(): {Vector3}
	local posicoes: {Vector3} = {}
	for _, objeto in Workspace:GetChildren() do
		if objeto:IsA("Model") and possuiHammer(objeto) then
			local root = objeto:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				table.insert(posicoes, root.Position)
			end
		end
	end
	return posicoes
end

--------------------------------------------------------------------------------
-- VERIFICAÇÃO DE HAMMER EM PRIMEIRA PESSOA
--------------------------------------------------------------------------------
local function verificarEExecutarAudioHammerFOV(meuTorso: BasePart)
	local agora = os.clock()
	if agora - ultimoTempoAudioHammerFOV < COOLDOWN_AUDIO_HAMMER_FOV then
		return
	end

	for _, objeto in Workspace:GetChildren() do
		if objeto:IsA("Model") and objeto ~= LocalPlayer.Character and possuiHammer(objeto) then
			local headHammer = objeto:FindFirstChild("Head") :: BasePart?
			local hrpHammer = objeto:FindFirstChild("HumanoidRootPart") :: BasePart?
			if headHammer and hrpHammer then
				local dist = (meuTorso.Position - hrpHammer.Position).Magnitude
				if dist <= 100 then
					local playerHammer = Players:GetPlayerFromCharacter(objeto)
					local estaEmPrimeiraPessoa = false
					local direcaoOlhar = headHammer.CFrame.LookVector

					if playerHammer then
						local camera = Workspace.CurrentCamera
						if playerHammer == LocalPlayer and camera then
							estaEmPrimeiraPessoa = (camera.CFrame.Position - headHammer.Position).Magnitude < 2
							direcaoOlhar = camera.CFrame.LookVector
						else
							estaEmPrimeiraPessoa = true
						end
					else
						estaEmPrimeiraPessoa = true
					end

					if estaEmPrimeiraPessoa then
						local vetorParaMim = (meuTorso.Position - headHammer.Position).Unit
						local dot = direcaoOlhar:Dot(vetorParaMim)

						if dot < 0.35 then
							ultimoTempoAudioHammerFOV = agora

							local s = Instance.new("Sound")
							s.Name = "HammerOutOfFOVSound"
							s.SoundId = AUDIO_HAMMER_OUT_OF_FOV_ID
							s.Volume = 1
							s.Looped = false
							s.Parent = meuTorso
							s:Play()
							s.Ended:Connect(function()
								s:Destroy()
							end)
							break
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- TWEEN E HIGHLIGHT HELPER
--------------------------------------------------------------------------------
local function interromperTweenGenerico(tweenRef: Tween?)
	if tweenRef then tweenRef:Cancel() end
end

local function transicionarHighlight(highlight: Highlight, corOutline: Color3, corFill: Color3, tempo: number, fillTrans: number, outlineTrans: number, callback: (() -> ())?): Tween?
	if not highlight or not highlight.Parent then return nil end
	
	local tweenInfo = TweenInfo.new(tempo, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenProps = {
		OutlineColor = corOutline,
		FillColor = corFill,
		FillTransparency = fillTrans,
		OutlineTransparency = outlineTrans
	}

	local tween = TweenService:Create(highlight, tweenInfo, tweenProps)
	if callback then tween.Completed:Connect(callback) end
	tween:Play()
	return tween
end

--------------------------------------------------------------------------------
-- PERSONAGENS
--------------------------------------------------------------------------------
local function registrarPersonagem(modelo: Model): DadosPersonagem?
	if personagensRegistrados[modelo] then return personagensRegistrados[modelo] end
	if possuiHammer(modelo) then return nil end

	local torso = modelo:FindFirstChild("Torso") :: BasePart?
	if not torso then return nil end

	local highlight = Instance.new("Highlight")
	highlight.Name = "UnifiedAnchorHighlight"
	highlight.Adornee = modelo
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = COR_CIANO_FILL
	highlight.OutlineColor = COR_CIANO_OUTLINE
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Enabled = false
	highlight.Parent = modelo

	local dados: DadosPersonagem = {
		Modelo = modelo,
		Torso = torso,
		Highlight = highlight,
		NoRaioArea = false,
		EstadoAncoradoLocal = false,
		EmPerigoHammer = false,
		EmAnimacaoVerde = false,
		EmAnimacaoDetector = false,
		TweenAtual = nil,
		ThreadVerde = nil,
		ThreadDetector = nil
	}

	personagensRegistrados[modelo] = dados
	return dados
end

local function desregistrarPersonagem(modelo: Model)
	local dados = personagensRegistrados[modelo]
	if dados then
		interromperTweenGenerico(dados.TweenAtual)
		if dados.ThreadVerde then task.cancel(dados.ThreadVerde) end
		if dados.ThreadDetector then task.cancel(dados.ThreadDetector) end
		if dados.Highlight and dados.Highlight.Parent then dados.Highlight:Destroy() end
		personagensRegistrados[modelo] = nil
	end
end

--------------------------------------------------------------------------------
-- DETECTOR
--------------------------------------------------------------------------------
local function dispararHighlightDetectorParaPersonagem(dados: DadosPersonagem)
	if not dados or not dados.Highlight or not dados.Highlight.Parent then return end

	dados.EmAnimacaoDetector = true
	interromperTweenGenerico(dados.TweenAtual)

	if dados.ThreadDetector then
		task.cancel(dados.ThreadDetector)
		dados.ThreadDetector = nil
	end

	dados.Highlight.Enabled = true
	dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_VERMELHO_OUTLINE, COR_VERMELHO_FILL, 0.3, 0.6, 0)

	dados.ThreadDetector = task.delay(0.3, function()
		task.wait(1.5)
		if dados.Highlight and dados.Highlight.Parent then
			dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_VERMELHO_OUTLINE, COR_VERMELHO_FILL, 0.5, 1, 1, function()
				if dados.Highlight then dados.Highlight.Enabled = false end
				dados.EmAnimacaoDetector = false
			end)
		else
			dados.EmAnimacaoDetector = false
		end
	end)
end

local function checarSomDetectorEAtivar(som: Sound)
	local detectorModel = som:FindFirstAncestor(NOME_DETECTOR)
	if not detectorModel or not detectorModel:IsA("Model") then return end

	local pivoPos = detectorModel:GetPivot().Position

	for _, modelo in Workspace:GetChildren() do
		if modelo:IsA("Model") then
			local hum = modelo:FindFirstChildOfClass("Humanoid")
			local torso = modelo:FindFirstChild("Torso") :: BasePart?
			if hum and hum.Health > 0 and torso then
				if (torso.Position - pivoPos).Magnitude <= RAIO_DETECTOR then
					local dados = registrarPersonagem(modelo)
					if dados then
						dispararHighlightDetectorParaPersonagem(dados)
					end
				end
			end
		end
	end
end

local function conectarSomDetector(som: Sound)
	if conexoesDetectores[som] then return end

	local parentDetector = som:FindFirstAncestor(NOME_DETECTOR)
	if parentDetector and parentDetector:IsA("Model") then
		local conexao = som:GetPropertyChangedSignal("IsPlaying"):Connect(function()
			if som.IsPlaying then
				checarSomDetectorEAtivar(som)
			end
		end)

		conexoesDetectores[som] = conexao

		if som.IsPlaying then
			checarSomDetectorEAtivar(som)
		end
	end
end

local function desconectarSomDetector(som: Sound)
	if conexoesDetectores[som] then
		conexoesDetectores[som]:Disconnect()
		conexoesDetectores[som] = nil
	end
end

for _, desc in Workspace:GetDescendants() do
	if desc:IsA("Sound") then conectarSomDetector(desc) end
end

Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Sound") then conectarSomDetector(desc) end
end)

Workspace.DescendantRemoving:Connect(function(desc)
	if desc:IsA("Sound") then desconectarSomDetector(desc) end
end)

--------------------------------------------------------------------------------
-- SCREENS & COMPUTERS (CORRIGIDO PARA MÚLTIPLOS HIGHLIGHTS VERMELHOS)
--------------------------------------------------------------------------------
local function encontrarModeloComputerAncestral(instancia: Instance): Model?
	local ultimoComputerEncontrado: Model? = nil
	local atual: Instance? = instancia.Parent

	while atual and atual ~= Workspace do
		if atual:IsA("Model") and string.sub(atual.Name, 1, 8) == "Computer" then
			ultimoComputerEncontrado = atual
		end
		atual = atual.Parent
	end

	return ultimoComputerEncontrado
end

local function registrarComputador(modeloComputer: Model): DadosComputador
	if computadoresRegistrados[modeloComputer] then
		return computadoresRegistrados[modeloComputer]
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ComputerScreenHighlight"
	highlight.Adornee = modeloComputer
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Enabled = false
	highlight.Parent = modeloComputer

	local dados: DadosComputador = {
		ModeloComputer = modeloComputer,
		Highlight = highlight,
		EstadoCor = "Nenhum",
		ThreadExpiracao = nil,
		TweenAtual = nil
	}

	computadoresRegistrados[modeloComputer] = dados
	return dados
end

local function aplicarHighlightComputador(dados: DadosComputador, tipoCor: "Vermelho" | "Verde")
	if not dados.Highlight or not dados.Highlight.Parent then return end

	-- Interrompe animações e timers pendentes para aceitar o novo evento
	interromperTweenGenerico(dados.TweenAtual)
	if dados.ThreadExpiracao then
		task.cancel(dados.ThreadExpiracao)
		dados.ThreadExpiracao = nil
	end

	dados.EstadoCor = tipoCor
	dados.Highlight.Enabled = true

	if tipoCor == "Vermelho" then
		dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_VERMELHO_OUTLINE, COR_VERMELHO_FILL, 0.5, 0.6, 0)
		
		-- Reinicia o timer de 30 segundos sem bloquear chamadas futuras
		dados.ThreadExpiracao = task.delay(30, function()
			if computadoresRegistrados[dados.ModeloComputer] == dados and dados.EstadoCor == "Vermelho" then
				if dados.Highlight and dados.Highlight.Parent then
					dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_VERMELHO_OUTLINE, COR_VERMELHO_FILL, 0.5, 1, 1, function()
						if dados.Highlight then dados.Highlight.Enabled = false end
						dados.EstadoCor = "Nenhum"
					end)
				end
			end
		end)

	elseif tipoCor == "Verde" then
		dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_VERDE_OUTLINE, COR_VERDE_FILL, 0.5, 0.6, 0)
		
		dados.ThreadExpiracao = task.delay(1.5, function()
			if computadoresRegistrados[dados.ModeloComputer] == dados and dados.EstadoCor == "Verde" then
				if dados.Highlight and dados.Highlight.Parent then
					dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_VERDE_OUTLINE, COR_VERDE_FILL, 0.5, 1, 1, function()
						if dados.Highlight then dados.Highlight.Enabled = false end
						dados.EstadoCor = "Nenhum"
					end)
				end
			end
		end)
	end
end

local function avaliarCorScreen(objetoScreen: Instance)
	if not objetoScreen or not objetoScreen.Parent then return end

	local corObjeto = extrairCorObjeto(objetoScreen)
	if not corObjeto then return end

	local modeloComputer = encontrarModeloComputerAncestral(objetoScreen)
	if not modeloComputer then return end

	local dadosComp = registrarComputador(modeloComputer)

	local distVermelho = obterDistanciaCor(corObjeto, COR_REF_VERMELHO)
	local distVerde = obterDistanciaCor(corObjeto, COR_REF_VERDE)
	local distVerdeClaro = obterDistanciaCor(corObjeto, COR_REF_VERDE_CLARO)

	local menorDistVerde = math.min(distVerde, distVerdeClaro)
	local ehVerde = (menorDistVerde < 0.65) or (corObjeto.G > 0.4 and corObjeto.G > (corObjeto.R + 0.15) and corObjeto.G > (corObjeto.B + 0.15))

	if ehVerde then
		aplicarHighlightComputador(dadosComp, "Verde")
	elseif distVermelho < 0.45 then
		aplicarHighlightComputador(dadosComp, "Vermelho")
	end
end

local function conectarMonitoramentoScreen(objeto: Instance)
	if conexoesScreens[objeto] then return end

	local nomeMin = string.lower(objeto.Name)
	if nomeMin == "screen" then
		local nomePropriedadeCor = obterNomePropriedadeCor(objeto)
		if nomePropriedadeCor then
			avaliarCorScreen(objeto)

			local sucesso, conexao = pcall(function()
				return objeto:GetPropertyChangedSignal(nomePropriedadeCor):Connect(function()
					avaliarCorScreen(objeto)
				end)
			end)

			if sucesso and conexao then
				conexoesScreens[objeto] = conexao
			end
		end
	end
end

for _, objeto in Workspace:GetDescendants() do conectarMonitoramentoScreen(objeto) end
Workspace.DescendantAdded:Connect(function(objeto) conectarMonitoramentoScreen(objeto) end)
Workspace.DescendantRemoving:Connect(function(objeto)
	if conexoesScreens[objeto] then
		conexoesScreens[objeto]:Disconnect()
		conexoesScreens[objeto] = nil
	end
end)

--------------------------------------------------------------------------------
-- HIGHLIGHTS DOS PERSONAGENS E PLATFORMSTAND
--------------------------------------------------------------------------------
local function processarHighlightsPersonagens(meuTorsoAncorado: boolean, minhaPosicao: Vector3, posicoesHammers: {Vector3})
	for _, objeto in Workspace:GetChildren() do
		if objeto:IsA("Model") then
			local humanoid = objeto:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				monitorarHumanoidPlatformStand(humanoid)

				if objeto ~= LocalPlayer.Character then
					if possuiHammer(objeto) then
						if personagensRegistrados[objeto] then desregistrarPersonagem(objeto) end
					else
						registrarPersonagem(objeto)
					end
				end
			end
		end
	end

	for modelo, dados in pairs(personagensRegistrados) do
		local torso = dados.Torso
		if not torso or not torso.Parent or not modelo or not modelo.Parent then
			desregistrarPersonagem(modelo)
			continue
		end

		if dados.EmAnimacaoDetector then continue end

		local estaAncorado = torso.Anchored
		local distanciaDoJogador = (torso.Position - minhaPosicao).Magnitude

		local hammerPerto = false
		for _, posHammer in posicoesHammers do
			if (posHammer - torso.Position).Magnitude <= DISTANCIA_MAX_DESFOCO then
				hammerPerto = true
				break
			end
		end

		if estaAncorado then
			if dados.EmAnimacaoVerde or not dados.EstadoAncoradoLocal then
				dados.EstadoAncoradoLocal = true
				dados.EmAnimacaoVerde = false
				
				if dados.ThreadVerde then
					task.cancel(dados.ThreadVerde)
					dados.ThreadVerde = nil
				end
			end
		end

		if dados.EstadoAncoradoLocal and not estaAncorado then
			dados.EstadoAncoradoLocal = false
			dados.EmAnimacaoVerde = true

			interromperTweenGenerico(dados.TweenAtual)
			if dados.ThreadVerde then task.cancel(dados.ThreadVerde) end

			dados.Highlight.Enabled = true
			dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_VERDE_OUTLINE, COR_VERDE_FILL, 0.5, 0.6, 0)

			dados.ThreadVerde = task.delay(0.5, function()
				task.wait(1.5)
				if personagensRegistrados[modelo] == dados and dados.Torso and not dados.Torso.Anchored then
					dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_VERDE_OUTLINE, COR_VERDE_FILL, 0.5, 1, 1, function()
						if dados.Highlight then dados.Highlight.Enabled = false end
						dados.EmAnimacaoVerde = false
					end)
				end
			end)

			continue
		end

		if (meuTorsoAncorado or estaAncorado) and not dados.EmAnimacaoVerde then
			if (distanciaDoJogador <= RAIO_AREA_ANCORA or estaAncorado) and not dados.NoRaioArea then
				dados.NoRaioArea = true
				dados.Highlight.Enabled = true

				if hammerPerto then
					dados.EmPerigoHammer = true
					dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_VERMELHO_OUTLINE, COR_VERMELHO_FILL, 0.5, 0.6, 0)
				else
					dados.EmPerigoHammer = false
					dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_CIANO_OUTLINE, COR_CIANO_FILL, 0.5, 0.6, 0)
				end

			elseif dados.NoRaioArea then
				if hammerPerto and not dados.EmPerigoHammer then
					dados.EmPerigoHammer = true
					interromperTweenGenerico(dados.TweenAtual)
					dados.Highlight.OutlineColor = COR_VERMELHO_OUTLINE
					dados.Highlight.FillColor = COR_VERMELHO_FILL
					dados.Highlight.FillTransparency = 0.6
					dados.Highlight.OutlineTransparency = 0

				elseif not hammerPerto and dados.EmPerigoHammer then
					dados.EmPerigoHammer = false
					dados.TweenAtual = transicionarHighlight(dados.Highlight, COR_CIANO_OUTLINE, COR_CIANO_FILL, 1.0, 0.6, 0)
				end
			end

			if distanciaDoJogador > RAIO_AREA_ANCORA and not estaAncorado and dados.NoRaioArea then
				dados.NoRaioArea = false
				dados.TweenAtual = transicionarHighlight(dados.Highlight, dados.Highlight.OutlineColor, dados.Highlight.FillColor, 0.5, 1, 1, function()
					if not dados.NoRaioArea and dados.Highlight then
						dados.Highlight.Enabled = false
					end
				end)
			end

		elseif not meuTorsoAncorado and not estaAncorado and not dados.EmAnimacaoVerde then
			if dados.NoRaioArea or dados.Highlight.Enabled then
				dados.NoRaioArea = false
				dados.TweenAtual = transicionarHighlight(dados.Highlight, dados.Highlight.OutlineColor, dados.Highlight.FillColor, 0.5, 1, 1, function()
					if dados.Highlight then dados.Highlight.Enabled = false end
				end)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- DETECÇÃO DE JOGADOR FOCADO (JOGO / ESPECTADOR)
--------------------------------------------------------------------------------
local function obterFocoECasoAlvo(camera: Camera, meuPersonagem: Model): (Vector3?, Player?, Model?)
	local subject = camera.CameraSubject
	local modeloAlvo: Model? = nil
	local playerAlvo: Player? = nil

	if subject then
		if subject:IsA("Humanoid") then
			if subject.Parent and subject.Parent:IsA("Model") then
				modeloAlvo = subject.Parent
			end
		elseif subject:IsA("BasePart") then
			if subject.Parent and subject.Parent:IsA("Model") then
				modeloAlvo = subject.Parent
			end
		end
	end

	if not modeloAlvo then
		modeloAlvo = meuPersonagem
	end

	if modeloAlvo then
		playerAlvo = Players:GetPlayerFromCharacter(modeloAlvo)
		local hrp = modeloAlvo:FindFirstChild("HumanoidRootPart") :: BasePart?
		local torso = modeloAlvo:FindFirstChild("Torso") :: BasePart?
		local pos = (hrp and hrp.Position) or (torso and torso.Position)
		return pos, playerAlvo, modeloAlvo
	end

	return nil, nil, nil
end

--------------------------------------------------------------------------------
-- MONITORAMENTO SURVIVOR CELL (BARRA DE VIDA X) + NÉVOA CRÍTICA
--------------------------------------------------------------------------------
local function obterTamanhoFillSurvivorCell(playerAlvo: Player): number?
	if not playerAlvo then return nil end

	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end

	local screenGui = playerGui:FindFirstChild("ScreenGui")
	if not screenGui then return nil end

	local roundBar = screenGui:FindFirstChild("RoundBar")
	if not roundBar then return nil end

	local statusBars = roundBar:FindFirstChild("StatusBars")
	if not statusBars then return nil end

	local nomeAlvo = playerAlvo.Name
	local displayNameAlvo = playerAlvo.DisplayName

	for i = 1, 4 do
		local survivorCell = statusBars:FindFirstChild("SurvivorCell" .. i)
		if survivorCell then
			local nameLabel = survivorCell:FindFirstChild("NameLabel") :: TextLabel?
			if nameLabel then
				local textoNome = nameLabel.Text
				if textoNome == nomeAlvo or textoNome == displayNameAlvo then
					local healthBar = survivorCell:FindFirstChild("HealthBar")
					if healthBar then
						local fill = healthBar:FindFirstChild("Fill") :: GuiObject?
						if fill and fill.Parent then
							return fill.AbsoluteSize.X
						end
					end
				end
			end
		end
	end

	return nil
end

local function aplicarEfeitosSurvivorCell(tamanhoX: number, fatorMultiplicador: number?)
	local mult = fatorMultiplicador or 1.0

	local rBase, gBase, bBase = 255, 255, 255
	local blurSizeBase = 0
	local tremorBase = 0

	if tamanhoX >= 110 then
		rBase, gBase, bBase = 255, 255, 255
		blurSizeBase = 0
		tremorBase = 0
		removerNevoaCritica()
	elseif tamanhoX >= 90 then
		rBase, gBase, bBase = 200, 245, 255
		blurSizeBase = 4
		tremorBase = 0
		removerNevoaCritica()
	elseif tamanhoX >= 75 then
		rBase, gBase, bBase = 150, 235, 255
		blurSizeBase = 8
		tremorBase = 0
		removerNevoaCritica()
	elseif tamanhoX >= 60 then
		rBase, gBase, bBase = 100, 225, 255
		blurSizeBase = 14
		tremorBase = 0
		removerNevoaCritica()
	elseif tamanhoX >= 45 then
		rBase, gBase, bBase = 50, 215, 255
		blurSizeBase = 20
		tremorBase = 0.12
		removerNevoaCritica()
	elseif tamanhoX >= 25 then
		rBase, gBase, bBase = 0, 200, 255
		blurSizeBase = 28
		tremorBase = 0.28
		removerNevoaCritica()
	else
		-- FASE CRÍTICA (X < 25 até 0):
		rBase, gBase, bBase = 0, 200, 255
		blurSizeBase = 28
		tremorBase = 0.28

		local nevoa = obterOuCriarNevoaCritica()
		nevoa.Parent = Lighting

		local progressoCritico = math.clamp(tamanhoX / 25, 0, 1)
		local visibilidadeStuds = 1 + (99 * progressoCritico)

		local densidadeNevea = math.clamp(1 - (visibilidadeStuds / 100), 0.35, 0.98) * mult
		nevoa.Density = densidadeNevea
		nevoa.Haze = (10 * (1 - progressoCritico)) * mult
		nevoa.Offset = 0
	end

	local r = math.clamp(255 - (255 - rBase) * mult, 0, 255)
	local g = math.clamp(255 - (255 - gBase) * mult, 0, 255)
	local b = math.clamp(255 - (255 - bBase) * mult, 0, 255)

	survivorCellCC.TintColor = Color3.fromRGB(r, g, b)
	survivorCellBlur.Size = blurSizeBase * mult
	tremorSurvivorCellAtual = tremorBase * mult
end

local function resetarEfeitosSurvivorCell()
	survivorCellCC.TintColor = Color3.fromRGB(255, 255, 255)
	survivorCellBlur.Size = 0
	tremorSurvivorCellAtual = 0
	removerNevoaCritica()
end

--------------------------------------------------------------------------------
-- LOOP PRINCIPAL (RENDERSTEP)
--------------------------------------------------------------------------------
RunService:BindToRenderStep(RENDER_ID, Enum.RenderPriority.Camera.Value + 1, function(deltaTime: number)
	local posicoesHammers = obterPosicoesHammersAtivos()

	local meuPersonagem = LocalPlayer.Character
	if not meuPersonagem or not meuPersonagem:IsDescendantOf(Workspace) then return end

	local meuTorso = meuPersonagem:FindFirstChild("Torso") :: BasePart?
	local minhaHumanoid = meuPersonagem:FindFirstChildOfClass("Humanoid")

	if not meuTorso or not minhaHumanoid or minhaHumanoid.Health <= 0 then return end

	----------------------------------------------------------------------------
	-- 0. CHECAGEM DE ÁUDIO DE FOV DO HAMMER EM PRIMEIRA PESSOA
	----------------------------------------------------------------------------
	verificarEExecutarAudioHammerFOV(meuTorso)

	----------------------------------------------------------------------------
	-- 1. SISTEMA DE HIGHLIGHTS E PLATFORMSTAND
	----------------------------------------------------------------------------
	processarHighlightsPersonagens(meuTorso.Anchored, meuTorso.Position, posicoesHammers)

	----------------------------------------------------------------------------
	-- 2. SUPORTE A ESPECTADOR & CAPTURA DE FOCO
	----------------------------------------------------------------------------
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local posicaoFocoCamera, playerAlvo, modeloAlvo = obterFocoECasoAlvo(camera, meuPersonagem)

	----------------------------------------------------------------------------
	-- 3. MONITORAMENTO SURVIVOR CELL (EFEITOS & NÉVOA CRÍTICA COM DECAIMENTO)
	----------------------------------------------------------------------------
	local torsoAlvo: BasePart? = nil
	if modeloAlvo then
		torsoAlvo = modeloAlvo:FindFirstChild("Torso") :: BasePart?
	end

	local estaAncoradoAgora = (torsoAlvo and torsoAlvo.Anchored) or false

	if estaAncoradoAgora then
		fatorSurvivorCellDecay = 1.0
		foiAncoradoAnteriormente = true
		jogadorAncoradoAnterior = playerAlvo
		
		if playerAlvo then
			local tamanhoX = obterTamanhoFillSurvivorCell(playerAlvo)
			if tamanhoX then
				aplicarEfeitosSurvivorCell(tamanhoX, 1.0)
			else
				resetarEfeitosSurvivorCell()
			end
		else
			resetarEfeitosSurvivorCell()
		end
	else
		if foiAncoradoAnteriormente and fatorSurvivorCellDecay > 0 then
			fatorSurvivorCellDecay = math.max(0, fatorSurvivorCellDecay - (deltaTime / 60))

			local playerParaVerificar = playerAlvo or jogadorAncoradoAnterior
			if playerParaVerificar then
				local tamanhoX = obterTamanhoFillSurvivorCell(playerParaVerificar)
				if tamanhoX and fatorSurvivorCellDecay > 0 then
					aplicarEfeitosSurvivorCell(tamanhoX, fatorSurvivorCellDecay)
				else
					foiAncoradoAnteriormente = false
					jogadorAncoradoAnterior = nil
					resetarEfeitosSurvivorCell()
				end
			else
				foiAncoradoAnteriormente = false
				jogadorAncoradoAnterior = nil
				resetarEfeitosSurvivorCell()
			end
		else
			foiAncoradoAnteriormente = false
			jogadorAncoradoAnterior = nil
			resetarEfeitosSurvivorCell()
		end
	end

	----------------------------------------------------------------------------
	-- 4. TREMOR DE CÂMERA E BLUR DO HAMMER
	----------------------------------------------------------------------------
	local menorDistanciaHammer: number? = nil

	if posicaoFocoCamera then
		for _, posHammer in posicoesHammers do
			if (posHammer - posicaoFocoCamera).Magnitude > 0.1 then
				local dist = (posHammer - posicaoFocoCamera).Magnitude
				if not menorDistanciaHammer or dist < menorDistanciaHammer then
					menorDistanciaHammer = dist
				end
			end
		end
	end

	local tremorAlvo = 0
	local blurAlvo = 0

	if menorDistanciaHammer then
		if menorDistanciaHammer <= DISTANCIA_MAX_TREMOR then
			if menorDistanciaHammer >= 35 then
				tremorAlvo = math.clamp(0.05 + (((50 - menorDistanciaHammer) / 15) * 0.10), 0.05, 0.15)
			elseif menorDistanciaHammer >= 20 then
				tremorAlvo = math.clamp(0.15 + (((35 - menorDistanciaHammer) / 15) * 0.20), 0.15, 0.35)
			elseif menorDistanciaHammer >= 10 then
				tremorAlvo = math.clamp(0.35 + (((20 - menorDistanciaHammer) / 10) * 0.25), 0.35, 0.60)
			else
				tremorAlvo = math.clamp(0.60 + (((10 - menorDistanciaHammer) / 10) * 0.40), 0.60, 1.00)
			end
		end

		if menorDistanciaHammer < DISTANCIA_MAX_DESFOCO then
			local pBlur = (DISTANCIA_MAX_DESFOCO - menorDistanciaHammer) / DISTANCIA_MAX_DESFOCO
			blurAlvo = math.clamp(pBlur * BLUR_MAXIMO, 0, BLUR_MAXIMO)
		end
	end

	local alpha = 1 - math.exp(-14 * deltaTime)
	intensidadeTremorAtual = intensidadeTremorAtual + (tremorAlvo - intensidadeTremorAtual) * alpha
	intensidadeBlurAtual = intensidadeBlurAtual + (blurAlvo - intensidadeBlurAtual) * alpha

	blurEffect.Size = (intensidadeBlurAtual < 0.01) and 0 or intensidadeBlurAtual

	local tremorTotal = math.max(intensidadeTremorAtual, tremorSurvivorCellAtual)

	if tremorTotal >= 0.001 then
		local frequencia = 14 + (tremorTotal * 6)
		tempoAcumulado = tempoAcumulado + (deltaTime * frequencia)

		local maxAngleX = math.rad(1.6) * tremorTotal
		local maxAngleY = math.rad(2.0) * tremorTotal
		local maxAngleZ = math.rad(1.0) * tremorTotal

		local noiseX = math.noise(tempoAcumulado, 0, 0) * maxAngleX
		local noiseY = math.noise(0, tempoAcumulado, 0) * maxAngleY
		local noiseZ = math.noise(0, 0, tempoAcumulado) * maxAngleZ

		camera.CFrame = camera.CFrame * CFrame.Angles(noiseX, noiseY, noiseZ)
	else
		intensidadeTremorAtual = 0
	end
end)

--------------------------------------------------------------------------------
-- LIMPEZA
--------------------------------------------------------------------------------
Workspace.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		local hum = child:FindFirstChildOfClass("Humanoid")
		if hum then desconectarHumanoidPlatformStand(hum) end
	end
	if personagensRegistrados[child] then
		desregistrarPersonagem(child)
	end
	if computadoresRegistrados[child] then
		local dados = computadoresRegistrados[child]
		if dados.ThreadExpiracao then task.cancel(dados.ThreadExpiracao) end
		interromperTweenGenerico(dados.TweenAtual)
		if dados.Highlight and dados.Highlight.Parent then dados.Highlight:Destroy() end
		computadoresRegistrados[child] = nil
	end
end)

script.Destroying:Connect(function()
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_ID)
	end)
	cancelarEfeitosDesmaioLocal()
	resetarEfeitosSurvivorCell()

	if blurEffect then blurEffect.Size = 0 end

	for objeto, conexao in pairs(conexoesScreens) do
		if conexao then conexao:Disconnect() end
	end
	table.clear(conexoesScreens)

	for humanoid, conexao in pairs(conexoesPlatformStand) do
		if conexao then conexao:Disconnect() end
	end
	table.clear(conexoesPlatformStand)

	for hum, th in pairs(threadsGeracaoSangue) do
		task.cancel(th)
	end
	table.clear(threadsGeracaoSangue)

	for som, conexao in pairs(conexoesDetectores) do
		if conexao then conexao:Disconnect() end
	end
	table.clear(conexoesDetectores)

	if conexoesAnchoredLocal then
		conexoesAnchoredLocal:Disconnect()
		conexoesAnchoredLocal = nil
	end

	for modelo, _ in pairs(personagensRegistrados) do
		desregistrarPersonagem(modelo)
	end
	for modelo, dados in pairs(computadoresRegistrados) do
		if dados.ThreadExpiracao then task.cancel(dados.ThreadExpiracao) end
		if dados.Highlight and dados.Highlight.Parent then dados.Highlight:Destroy() end
	end
end)
