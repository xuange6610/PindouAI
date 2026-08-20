from pathlib import Path

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

from ..config import get_settings

router = APIRouter(prefix="/collection", tags=["collection"])


@router.get("/file")
async def original_file(path: str = Query(min_length=1, max_length=1000)) -> FileResponse:
    settings = get_settings()
    if not settings.collection_source_dir:
        raise HTTPException(status_code=503, detail="Original collection is not configured")
    root = Path(settings.collection_source_dir).expanduser().resolve()
    candidate = (root / Path(path.replace("\\", "/"))).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="Invalid collection path") from error
    if not candidate.is_file():
        raise HTTPException(status_code=404, detail="Original image not found")
    return FileResponse(candidate, filename=candidate.name)
