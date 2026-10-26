import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

String fileErrorMessage(BuildContext context, Object? error) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  if (error is ApiException) {
    final specific = switch (error.errorCode) {
      'worker_too_old' =>
        zh
            ? '这台电脑的云枢终端版本过旧，请更新后重试。'
            : 'Update Corterm on this computer and retry.',
      'worker_offline' =>
        zh
            ? '电脑已离线，请启动电脑上的云枢终端后重试。'
            : 'The computer is offline. Start Corterm on it and retry.',
      'path_invalid' => zh ? '名称或路径无效，或目标已存在。请检查后重试。' : 'The name or path is invalid, or the target already exists. Check and retry.',
      'file_too_large' =>
        zh
            ? '文件超过当前传输大小限制。'
            : 'The file exceeds the current transfer size limit.',
      'sha_mismatch' =>
        zh ? '文件校验失败，请重新传输。' : 'File verification failed. Retry the transfer.',
      _ => null,
    };
    if (specific != null) return specific;
    if (error.statusCode >= 500) {
      return zh
          ? '电脑上的文件服务发生错误。请更新或重启该电脑上的云枢终端后重试。'
          : 'The computer’s file service failed. Update or restart Corterm on that computer and retry.';
    }
    if (error.statusCode == 401 || error.statusCode == 403) {
      return zh
          ? '没有访问此文件的权限，请检查登录状态和电脑上的目录权限。'
          : 'Access denied. Check your sign-in and folder permissions on the computer.';
    }
    if (error.statusCode == 404) {
      return zh
          ? '文件或目录已不存在，请返回上一级后刷新。'
          : 'This file or folder no longer exists. Go back and refresh.';
    }
  }
  return zh
      ? '暂时无法完成文件操作，请检查电脑是否在线后重试。'
      : 'Unable to complete the file operation. Check that the computer is online and retry.';
}
