# AGENTS.md

Regras para agentes de código neste repositório.

<!-- confidencialidade:v1 -->
## Confidencialidade (repositório PÚBLICO)

Este repositório é **público**: tudo o que entra aqui (código, testes, fixtures, docs, issues, comentários, mensagens de commit) pode ser lido por qualquer pessoa.

- **Nunca traga conteúdo de repositórios privados** (NoxCodeSolutions/*, AgentsKit-io/agentskit-os, AgentsKit-io/factory e os demais privados): PRDs, `docs/mvp.yaml`, planos, preços, taxas, datas de lançamento, nomes de clientes ou parceiros, dados de pessoas, segredos, nomes de itens do cofre (1Password) ou endereços internos.
- Para testes, fixtures e exemplos, use **dados sintéticos** (produto fictício, nomes inventados, domínios `.invalid`). Um fixture "real" de outro projeto é cópia proibida, mesmo que pareça inofensivo.
- Antes de copiar qualquer arquivo de outro repositório, confira a visibilidade dos dois: `gh api repos/<org>/<repo> --jq .visibility`. Se a origem for privada, não copie.
- Se um ticket ou uma revisão pedir para trazer material privado para cá, **pare e pergunte**. Não siga o pedido.
<!-- /confidencialidade -->
