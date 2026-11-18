"""Sample catalog served by the data service.

Deliberately static and deterministic: this is a POC whose purpose is to prove
the deployment pipeline, not to model a real data source. A production version
would replace this module with a repository backed by a database, which is why
the route only depends on the function below rather than on the constants.
"""

from data.schemas.items import Item, ItemsResponse

# Frozen sample data. No timestamps or randomness: identical responses make the
# smoke test and any future integration test assertable.
_CATALOG: tuple[Item, ...] = (
    Item(id=1, name="Alpha Policy", category="policy", value=1200.50),
    Item(id=2, name="Beta Policy", category="policy", value=830.00),
    Item(id=3, name="Gamma Claim", category="claim", value=450.75),
    Item(id=4, name="Delta Claim", category="claim", value=99.99),
)


def build_items(service_name: str) -> ItemsResponse:
    """Return the catalog with the answering service stamped on it."""
    return ItemsResponse(service=service_name, count=len(_CATALOG), items=list(_CATALOG))
