#pragma once
inline int gCurrentTexture = -1;
inline int failedallocations = 0, textureresets = 0;
inline void* glGetTexturePointer(int) { static unsigned data; return &data; }
inline void* glGetColorTablePointer(int) { static unsigned data; return &data; }
inline constexpr int GL_FLIP_NONE=0, GL_FLIP_H=1, GL_FLIP_V=2, GL_RGBA=3, GL_RGB8_A5=4, GL_RGB32_A3=5;
inline constexpr int GL_TRANS_MANUALSORT=0, TEXGEN_OFF=0, TEXTURE_SIZE_256=5;
struct glImage { int width, height, u_off, v_off, textureID; };
template<class... T> void glResetTextures(T...) { ++textureresets; }
template<class... T> void glDeleteTextures(T...) {}
template<class... T> void glBindTexture(T...) {}
inline void glGenTextures(int count, int* ids) { static int next=1; while(count--) *ids++=next++; }
template<class... T> bool glTexImage2D(T...) { if (failedallocations) { --failedallocations; return false; } return true; }
template<class... T> void glColorTableEXT(T...) {}
template<class... T> void glBegin2D(T...) {}
template<class... T> void glEnd2D(T...) {}
template<class... T> void glFlush(T...) {}
template<class... T> void glPolyFmt(T...) {}
template<class... T> void glBoxFilled(T...) {}
template<class... T> void glColor(T...) {}
template<class... T> void glSprite(T...) {}
template<class... T> void glSpriteRotateScaleXY(T...) {}
template<class... T> void glPushMatrix(T...) {}
template<class... T> void glPopMatrix(T...) {}
template<class... T> void glTranslatef32(T...) {}
template<class... T> void glRotateZi(T...) {}
template<class... T> void glSpriteScaleXY(T...) {}
template<class... T> void glTriangleFilledGradient(T...) {}
