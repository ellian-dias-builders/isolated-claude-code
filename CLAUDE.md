# >>> buildersos >>>
<!-- Bloco gerenciado pelo buildersOS — não edite à mão (o instalador sobrescreve). -->

## buildersOS

Este projeto usa o buildersOS (Platform Builders): agentes, skills e workflows
servidos sob demanda pelo servidor MCP `buildersos`.

**Regra de arranque (obrigatória):** antes de iniciar QUALQUER tarefa de
desenvolvimento (implementar, corrigir, planejar, revisar), chame a tool MCP
`route_request` com o pedido do usuário e `model` = o id exato do seu modelo
(o que consta no seu system prompt), e trate o retorno como autoritativo:

1. Adote a persona de `persona.content`.
2. Se `delegate_to` listar subagents, delegue a eles (estão em `.claude/agents/`).
3. Aplique as skills de `skills_inline`; carregue `skills_available` com
   `load_skill` quando o contexto pedir.
4. Siga as `directives` durante toda a tarefa.

Se o domínio mudar no meio do caminho, chame `route_request` de novo.

**Anúncio de especialista:** ao aplicar um agente, o usuário DEVE ver
`🤖 Applying knowledge of @[agent-name]...`. Anuncie **apenas** um agente que
você carregou — via `persona.content` do `route_request` ou `load_agent("X")`.
Se preferir outro agente, carregue-o antes; se responder do próprio
conhecimento, diga isso e não anuncie agente nenhum.

**Workflows:** disponíveis como slash commands (`/mcp__buildersos__<nome>`).
Prefira-os quando o usuário pedir explicitamente um fluxo.

Se o servidor estiver indisponível, avise que as convenções da empresa não
estão sendo aplicadas e prossiga em modo genérico.
# <<< buildersos <<<
