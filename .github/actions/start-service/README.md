# start-service

Fonte da action composta `AgentsKit-io/.github/.github/actions/start-service` (cópia de referência mantida aqui; quem
tem a permissão `workflows` publica no repo `.github`). Guia de troca e motivo da escolha: manual da fábrica,
seção "Como um repo sobe banco no CI".

Troca de `services:` (exemplo com Postgres e Mongo):

```yaml
steps:
  - uses: actions/checkout@v4
  - id: pg
    uses: AgentsKit-io/.github/.github/actions/start-service@main
    with:
      name: postgres
      image: postgres:16
      port: 5432
      env: |
        POSTGRES_PASSWORD=postgres
      health-cmd: pg_isready -U postgres
  - id: mongo
    uses: AgentsKit-io/.github/.github/actions/start-service@main
    with:
      name: mongo
      image: mongo:7
      port: 27017
      health-cmd: mongosh --quiet --eval "db.adminCommand('ping').ok"
  - run: pnpm test
    env:
      DATABASE_URL: postgres://postgres:postgres@127.0.0.1:${{ steps.pg.outputs.host-port }}/postgres
      MONGO_URL: mongodb://127.0.0.1:${{ steps.mongo.outputs.host-port }}
  - if: always()
    uses: AgentsKit-io/.github/.github/actions/start-service@main
    with: { mode: stop, name: postgres }
  - if: always()
    uses: AgentsKit-io/.github/.github/actions/start-service@main
    with: { mode: stop, name: mongo }
```
