import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One explicit transfer, shared by endpoint negotiation, HTTP and P2P.
class FileTransferControl extends ChangeNotifier {
  final cancelToken = CancelToken();
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String route = 'negotiating';
  int transferred = 0;
  int total = 0;
  bool switching = false;
  VoidCallback? abortChannel;
  void cancel() {
    if (cancelToken.isCancelled) return;
    cancelToken.cancel('Cancelled by user');
    abortChannel?.call();
  }

  void attempt(String value) {
    switching = route != 'negotiating' && route != value;
    route = value;
    transferred = 0;
    total = 0;
    if (!_disposed) notifyListeners();
  }

  void progress(int count, int size) {
    transferred = count;
    total = size;
    if (!_disposed) notifyListeners();
  }

  Future<T> guard<T>(Future<T> operation) => Future.any([
    operation,
    cancelToken.whenCancel.then<T>((error) => throw error),
  ]);
  void checkCancelled() {
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
  }
}
