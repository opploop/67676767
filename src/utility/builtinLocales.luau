--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Built-in translations for the library's own chrome - every source string wrapped in
-- locale.t() across src/, in English (the canonical source text and also its own lookup key -
-- see locale.luau). English itself has no table here; missing a locale entirely already falls
-- back to the source string unchanged, so an "en" table would just be a copy of every key onto
-- itself. Covers Portuguese and Spanish only, the two explicitly asked for alongside English -
-- a dev can layer more languages on top with their own Window:RegisterTranslations() call, or
-- override any entry here the same way (a registered table always wins over these).
--
-- Element/control *names* a dev supplies (a toggle's "name", a button's "name", and so on)
-- aren't covered here - those are dev content, not library chrome, and were never routed through
-- locale.t() to begin with. Deliberately out of scope for the same reason element values, slider
-- readouts and keybind keys already are (see locale.luau's own header comment): translating a
-- dev's own labels for them would be guessing at meaning the library doesn't have.

return {
    pt = {
        ["%s is bound to %s. Kept %s."] = "%s está vinculado a %s. Mantido %s.",
        ["%s is the menu toggle key. Kept %s."] = "%s é a tecla de abrir/fechar o menu. Mantido %s.",
        ["An asset couldn't be cached and won't appear."] = "Um recurso não pôde ser armazenado em cache e não vai aparecer.",
        ["Configuration copied"] = "Configuração copiada",
        ["Couldn't delete configuration"] = "Não foi possível excluir a configuração",
        ["Couldn't export configuration"] = "Não foi possível exportar a configuração",
        ["Couldn't load configuration"] = "Não foi possível carregar a configuração",
        ["Couldn't save configuration"] = "Não foi possível salvar a configuração",
        ["Deleted configuration"] = "Configuração excluída",
        ["Error, log recorded in console."] = "Erro, registro salvo no console.",
        ["Imported configuration"] = "Configuração importada",
        ["Keybind unavailable"] = "Atalho indisponível",
        ["Loaded configuration"] = "Configuração carregada",
        ["Name your configuration first"] = "Nomeie sua configuração primeiro",
        ["No results"] = "Nenhum resultado",
        ["No results found"] = "Nenhum resultado encontrado",
        ["Paste a configuration first"] = "Cole uma configuração primeiro",
        ["Paste it anywhere to share it"] = "Cole em qualquer lugar para compartilhar",
        ["Pick a configuration to delete"] = "Escolha uma configuração para excluir",
        ["Pick a configuration to load"] = "Escolha uma configuração para carregar",
        ["Recording"] = "Gravando",
        ["Saved configuration"] = "Configuração salva",
        ["Search all pages"] = "Pesquisar em todas as páginas",
        ["Search..."] = "Pesquisar...",
        ["Secure mode"] = "Modo seguro",
        ["Signed in as"] = "Conectado como",
        ["Some assets couldn't be cached and won't appear."] = "Alguns recursos não puderam ser armazenados em cache e não vão aparecer.",
        ["Tap to show"] = "Toque para mostrar",
        ["That doesn't look like a valid configuration"] = "Isso não parece ser uma configuração válida",
        ["Various"] = "Vários",
        ["Step %d of %d"] = "Passo %d de %d",
        ["Next"] = "Próximo",
        ["Finish"] = "Concluir",
        ["Skip"] = "Pular",
    },
    es = {
        ["%s is bound to %s. Kept %s."] = "%s está vinculado a %s. Se mantuvo %s.",
        ["%s is the menu toggle key. Kept %s."] = "%s es la tecla para abrir/cerrar el menú. Se mantuvo %s.",
        ["An asset couldn't be cached and won't appear."] = "No se pudo almacenar en caché un recurso y no aparecerá.",
        ["Configuration copied"] = "Configuración copiada",
        ["Couldn't delete configuration"] = "No se pudo eliminar la configuración",
        ["Couldn't export configuration"] = "No se pudo exportar la configuración",
        ["Couldn't load configuration"] = "No se pudo cargar la configuración",
        ["Couldn't save configuration"] = "No se pudo guardar la configuración",
        ["Deleted configuration"] = "Configuración eliminada",
        ["Error, log recorded in console."] = "Error, registro guardado en la consola.",
        ["Imported configuration"] = "Configuración importada",
        ["Keybind unavailable"] = "Atajo no disponible",
        ["Loaded configuration"] = "Configuración cargada",
        ["Name your configuration first"] = "Primero nombra tu configuración",
        ["No results"] = "Sin resultados",
        ["No results found"] = "No se encontraron resultados",
        ["Paste a configuration first"] = "Pega una configuración primero",
        ["Paste it anywhere to share it"] = "Pégala donde quieras para compartirla",
        ["Pick a configuration to delete"] = "Elige una configuración para eliminar",
        ["Pick a configuration to load"] = "Elige una configuración para cargar",
        ["Recording"] = "Grabando",
        ["Saved configuration"] = "Configuración guardada",
        ["Search all pages"] = "Buscar en todas las páginas",
        ["Search..."] = "Buscar...",
        ["Secure mode"] = "Modo seguro",
        ["Signed in as"] = "Conectado como",
        ["Some assets couldn't be cached and won't appear."] = "Algunos recursos no se pudieron almacenar en caché y no aparecerán.",
        ["Tap to show"] = "Toca para mostrar",
        ["That doesn't look like a valid configuration"] = "Esto no parece ser una configuración válida",
        ["Various"] = "Varios",
        ["Step %d of %d"] = "Paso %d de %d",
        ["Next"] = "Siguiente",
        ["Finish"] = "Finalizar",
        ["Skip"] = "Omitir",
    },
}
