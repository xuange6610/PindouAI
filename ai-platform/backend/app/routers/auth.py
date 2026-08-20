from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_session
from ..models import User
from ..schemas import TokenResponse, UserCreate, UserRead
from ..security import create_access_token, current_user, hash_password, verify_password


router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(payload: UserCreate, session: AsyncSession = Depends(get_session)) -> TokenResponse:
    query = select(User).where(
        or_(User.email == payload.email.lower(), User.phone == payload.phone)
        if payload.phone
        else User.email == payload.email.lower()
    )
    if (await session.execute(query)).scalar_one_or_none() is not None:
        raise HTTPException(status_code=409, detail="邮箱或手机号已注册")
    user = User(
        email=payload.email.lower(),
        phone=payload.phone,
        display_name=payload.display_name,
        password_hash=hash_password(payload.password),
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return TokenResponse(access_token=create_access_token(user), user=UserRead.model_validate(user))


@router.post("/login", response_model=TokenResponse)
async def login(
    form: OAuth2PasswordRequestForm = Depends(),
    session: AsyncSession = Depends(get_session),
) -> TokenResponse:
    identifier = form.username.strip().lower()
    user = (
        await session.execute(select(User).where(or_(User.email == identifier, User.phone == identifier)))
    ).scalar_one_or_none()
    if user is None or not verify_password(form.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="账号或密码错误")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="账号已停用")
    return TokenResponse(access_token=create_access_token(user), user=UserRead.model_validate(user))


@router.get("/me", response_model=UserRead)
async def me(user: User = Depends(current_user)) -> User:
    return user
