/*
 ============================================================================
 Name        : hev-jni.h
 Author      : hev <r@hev.cc>
 Copyright   : Copyright (c) 2019 - 2023 hev
 Description : Java Native Interface
 ============================================================================
 */

#ifndef __HEV_JNI_H__
#define __HEV_JNI_H__

#if defined(ANDROID) && defined(ENABLE_LIBRARY)
void hev_jni_tunnel_ready (void);
#endif

#endif /* __HEV_JNI_H__ */
