import hashlib
import os
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..database import get_session
from ..models import FileAsset, User
from ..schemas import FileRead
from ..security import current_user


router = APIRouter(prefix="/files", tags=["files"])


@router.post("", response_model=FileRead, status_code=201)
async def upload_file(
    file: UploadFile,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> FileAsset:
    settings = get_settings()
    content = await file.read(settings.max_upload_bytes + 1)
    if len(content) > settings.max_upload_bytes:
        raise HTTPException(status_code=413, detail="文件超过上传大小限制")
    if not content:
        raise HTTPException(status_code=400, detail="文件为空")
    digest = hashlib.sha256(content).hexdigest()
    owner_directory = Path(settings.upload_directory) / user.id
    owner_directory.mkdir(parents=True, exist_ok=True)
    storage_path = owner_directory / digest
    temporary = owner_directory / f".{digest}.tmp"
    temporary.write_bytes(content)
    os.replace(temporary, storage_path)
    asset = FileAsset(
        user_id=user.id,
        original_name=(file.filename or "file")[:255],
        storage_path=str(storage_path),
        mime_type=(file.content_type or "application/octet-stream")[:120],
        size_bytes=len(content),
        sha256=digest,
    )
    session.add(asset)
    await session.commit()
    await session.refresh(asset)
    return asset
