import 'dart:convert';

const supportedNodeLinkHint =
    '支持 VMess、VLESS、Trojan、SS、Hysteria2、TUIC、AnyTLS、SOCKS5、HTTP/HTTPS 节点链接';

// A query option must be consumed explicitly, so a new transport/security
// extension cannot accidentally be imported with its required settings lost.
class _Options {
  _Options(Uri uri) : values = Map.of(uri.queryParameters);
  final Map<String, String> values;

  String take(List<String> keys, [String fallback = '']) {
    String? result;
    for (final key in keys) {
      final value = values.remove(key);
      if (value == null) continue;
      if (result != null && result != value) {
        throw FormatException('节点参数别名冲突：${keys.first}');
      }
      result = value;
    }
    return result ?? fallback;
  }

  bool? flag(List<String> keys) {
    final value = take(keys);
    if (value.isEmpty) return null;
    if (['1', 'true'].contains(value.toLowerCase())) return true;
    if (['0', 'false'].contains(value.toLowerCase())) return false;
    throw FormatException('节点参数 ${keys.first} 必须是 true/false 或 1/0');
  }

  void finish() {
    for (final key in ['remarks', 'group']) {
      values.remove(key);
    }
    if (values.isNotEmpty) {
      // Do not echo values: authentication information may be in the query.
      throw const FormatException('链接包含暂不支持的参数，请使用 YAML 配置导入');
    }
  }
}

String _decode64(String value) {
  try {
    return utf8.decode(base64.decode(base64.normalize(value)));
  } catch (_) {
    throw const FormatException('节点链接的 Base64 格式无效');
  }
}

String _required(String value, String label) {
  if (value.isEmpty) throw FormatException('节点缺少$label');
  return value;
}

String _uuid(String value) {
  if (!RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
      .hasMatch(value)) {
    throw const FormatException('节点 UUID 格式无效');
  }
  return value;
}

void _tls(Map<String, dynamic> node, _Options q, String sniKey,
    {bool clientFingerprint = true}) {
  final sni = q.take(['sni', 'peer', 'serverName', 'servername']);
  if (sni.isNotEmpty) node[sniKey] = sni;
  final insecure = q.flag(['insecure', 'allowInsecure', 'skip-cert-verify']);
  if (insecure != null) node['skip-cert-verify'] = insecure;
  final alpn = q.take(['alpn']);
  if (alpn.isNotEmpty) {
    node['alpn'] = alpn
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
  }
  if (clientFingerprint) {
    final fp = q.take(['fp', 'client-fingerprint']);
    if (fp.isNotEmpty) node['client-fingerprint'] = fp;
  }
}

void _transport(Map<String, dynamic> node, _Options q) {
  var network = q.take(['type', 'network'], 'tcp');
  if (network.isEmpty) network = 'tcp';
  final header = q.take(['headerType'], 'none');
  if (network == 'tcp' && header == 'http' && node['type'] == 'vless') {
    network = 'http';
  } else if (header.isNotEmpty && header != 'none') {
    throw const FormatException('暂不支持此传输伪装类型');
  }
  final allowed = node['type'] == 'vless'
      ? ['tcp', 'ws', 'http', 'h2', 'grpc', 'xhttp']
      : ['tcp', 'ws', 'grpc'];
  if (!allowed.contains(network)) {
    throw const FormatException('暂不支持此节点传输类型，请使用 YAML 配置导入');
  }
  node['network'] = network;
  if (network == 'tcp') return;
  if (network == 'grpc') {
    final service = q.take(['serviceName', 'service-name', 'path']);
    final mode = q.take(['mode'], 'gun');
    if (mode != 'gun' && mode.isNotEmpty) {
      throw const FormatException('暂不支持此 gRPC 模式');
    }
    node['grpc-opts'] = {'grpc-service-name': service};
    return;
  }
  final path = q.take(['path'], '/');
  final host = q.take(['host']);
  if (network == 'xhttp') {
    final mode = q.take(['mode'], 'auto');
    if (!['auto', 'stream-one', 'stream-up', 'packet-up'].contains(mode)) {
      throw const FormatException('XHTTP 模式无效');
    }
    node['xhttp-opts'] = {
      'path': path,
      'mode': mode,
      if (host.isNotEmpty) 'host': host,
    };
  } else if (network == 'ws') {
    final opts = <String, dynamic>{
      'path': path,
      if (host.isNotEmpty) 'headers': {'Host': host},
    };
    final early = q.take(['ed']);
    if (early.isNotEmpty) {
      final count = int.tryParse(early);
      if (count == null || count < 0) {
        throw const FormatException('WebSocket early data 大小无效');
      }
      opts['max-early-data'] = count;
    }
    final earlyHeader = q.take(['eh']);
    if (earlyHeader.isNotEmpty) opts['early-data-header-name'] = earlyHeader;
    node['ws-opts'] = opts;
  } else {
    final hosts = host.split(',').where((v) => v.isNotEmpty).toList();
    node[network == 'h2' ? 'h2-opts' : 'http-opts'] = network == 'h2'
        ? {'path': path, if (hosts.isNotEmpty) 'host': hosts}
        : {
            'method': 'GET',
            'path': path.split(','),
            if (hosts.isNotEmpty) 'headers': {'Host': hosts},
          };
  }
}

void _reality(Map<String, dynamic> node, _Options q) {
  final key = _required(q.take(['pbk', 'public-key']), 'Reality 公钥');
  try {
    if (base64.decode(base64.normalize(key)).length != 32) {
      throw const FormatException();
    }
  } catch (_) {
    throw const FormatException('Reality 公钥格式无效');
  }
  final sid = q.take(['sid', 'short-id']);
  if (!RegExp(r'^[0-9a-fA-F]{0,16}$').hasMatch(sid) || sid.length.isOdd) {
    throw const FormatException('Reality short-id 格式无效');
  }
  q.take(['spx']); // Xray spider path has no corresponding Mihomo option.
  node['reality-opts'] = {
    'public-key': base64Url
        .encode(base64.decode(base64.normalize(key)))
        .replaceAll('=', ''),
    'short-id': sid,
  };
}

void _ssPlugin(Map<String, dynamic> node, String value) {
  if (value.isEmpty) return;
  final parts = value.split(';');
  final plugin = parts.removeAt(0);
  final opts = <String, String>{};
  for (final part in parts.where((v) => v.isNotEmpty)) {
    final separator = part.indexOf('=');
    final key = separator < 0 ? part : part.substring(0, separator);
    if (opts.containsKey(key)) throw const FormatException('SS 插件参数重复');
    opts[key] = separator < 0 ? 'true' : part.substring(separator + 1);
  }
  final output = <String, dynamic>{};
  if (['obfs-local', 'simple-obfs', 'obfs'].contains(plugin)) {
    final mode = opts.remove('obfs') ?? opts.remove('mode') ?? '';
    if (!['http', 'tls'].contains(mode)) {
      throw const FormatException('SS obfs 模式必须是 http 或 tls');
    }
    output['mode'] = mode;
    final host = opts.remove('obfs-host') ?? opts.remove('host');
    if (host != null) output['host'] = host;
    node['plugin'] = 'obfs';
  } else if (plugin == 'v2ray-plugin') {
    final mode = opts.remove('mode') ?? 'websocket';
    if (mode != 'websocket') {
      throw const FormatException('SS 插件仅支持 WebSocket 模式');
    }
    output['mode'] = mode;
    for (final key in ['host', 'path']) {
      final value = opts.remove(key);
      if (value != null) output[key] = value;
    }
    for (final key in ['tls', 'mux']) {
      final value = opts.remove(key);
      if (value == null) continue;
      if (!['true', 'false', '1', '0'].contains(value)) {
        throw const FormatException('SS 插件布尔参数无效');
      }
      output[key] = value == 'true' || value == '1';
    }
    node['plugin'] = plugin;
  } else {
    throw const FormatException('暂不支持此 SS 插件，请使用 YAML 配置导入');
  }
  if (opts.isNotEmpty) throw const FormatException('暂不支持此 SS 插件参数');
  node['plugin-opts'] = output;
}

/// Converts supported share URIs into Mihomo proxy maps. Errors never include
/// the URI or its credentials, since they are displayed directly by the UI.
Map<String, dynamic> parseShareLink(String input) {
  try {
    return _parseShareLink(input);
  } on FormatException catch (error) {
    throw FormatException(error.message);
  } catch (_) {
    throw const FormatException('节点链接格式无效');
  }
}

Map<String, dynamic> _parseShareLink(String input) {
  if (input.isEmpty ||
      input.length > 1024 * 1024 ||
      RegExp(r'\s|%(?![0-9a-fA-F]{2})').hasMatch(input)) {
    throw const FormatException('请输入一个有效的节点链接');
  }
  var value = input;
  // Legacy SS encodes the entire method:password@host:port, SIP002 only
  // encodes userinfo; split suffixes before decoding to preserve labels.
  if (value.startsWith('ss://')) {
    final suffix = value.indexOf(RegExp(r'[?#]'), 5);
    final body = suffix < 0 ? value.substring(5) : value.substring(5, suffix);
    if (!body.contains('@')) {
      final decoded = _decode64(body);
      final at = decoded.lastIndexOf('@');
      if (at < 0) throw const FormatException('SS 地址或认证信息无效');
      final credentials =
          base64Url.encode(utf8.encode(decoded.substring(0, at)));
      value =
          'ss://$credentials${decoded.substring(at)}${suffix < 0 ? '' : value.substring(suffix)}';
    }
  }
  // Uri normalizes an explicit :0 away for schemes whose default port is 0.
  // Validate the original authority before using its normalized representation.
  final schemeEnd = value.indexOf('://');
  if (schemeEnd < 0) throw const FormatException('节点链接格式无效');
  final authority =
      value.substring(schemeEnd + 3).split(RegExp(r'[/?#]')).first;
  final endpoint = authority.substring(authority.lastIndexOf('@') + 1);
  final portStart = endpoint.startsWith('[')
      ? endpoint.indexOf(']') + 1
      : endpoint.lastIndexOf(':');
  int? explicitPort;
  if (portStart >= 0 &&
      portStart < endpoint.length &&
      endpoint[portStart] == ':') {
    final rawPort = endpoint.substring(portStart + 1);
    explicitPort = int.tryParse(rawPort);
    if (!RegExp(r'^\d+$').hasMatch(rawPort) ||
        explicitPort == null ||
        explicitPort < 1 ||
        explicitPort > 65535) {
      throw const FormatException('节点端口必须在 1–65535 之间');
    }
  }
  Uri uri;
  try {
    uri = Uri.parse(value);
    // Force decoding here, preventing malformed escapes from reaching YAML.
    Uri.decodeComponent(uri.userInfo);
    Uri.decodeComponent(uri.fragment);
  } catch (_) {
    throw const FormatException('节点链接格式无效');
  }
  const schemes = [
    'vless',
    'trojan',
    'ss',
    'hysteria2',
    'hy2',
    'tuic',
    'anytls',
    'socks',
    'socks5',
    'http',
    'https'
  ];
  if (!schemes.contains(uri.scheme)) {
    throw const FormatException(supportedNodeLinkHint);
  }
  if (uri.host.isEmpty || (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('节点地址或路径无效');
  }
  final scheme = uri.scheme;
  final type = switch (scheme) {
    'hy2' => 'hysteria2',
    'socks' => 'socks5',
    'https' => 'http',
    _ => scheme,
  };
  if (type == 'ss' && explicitPort == null) {
    throw const FormatException('SS 节点缺少端口');
  }
  final port = explicitPort ??
      (type == 'socks5'
          ? 1080
          : scheme == 'http'
              ? 80
              : 443);
  if (port < 1 || port > 65535) {
    throw const FormatException('节点端口必须在 1–65535 之间');
  }
  final q = _Options(uri);
  if (uri.queryParametersAll.values.any((v) => v.length > 1)) {
    throw const FormatException('节点链接参数重复');
  }
  final node = <String, dynamic>{
    'name': uri.fragment.isEmpty
        ? '${scheme.toUpperCase()} ${uri.host}:$port'
        : Uri.decodeComponent(uri.fragment),
    'type': type,
    'server': uri.host,
    'port': port,
  };
  final auth = Uri.decodeComponent(uri.userInfo);
  if (type == 'http' || type == 'socks5') {
    final separator = uri.userInfo.indexOf(':');
    if (auth.isNotEmpty) {
      node['username'] = Uri.decodeComponent(
          separator < 0 ? uri.userInfo : uri.userInfo.substring(0, separator));
      if (separator >= 0) {
        node['password'] =
            Uri.decodeComponent(uri.userInfo.substring(separator + 1));
      }
    }
    if (scheme == 'https') node['tls'] = true;
    if (type == 'socks5') node['udp'] = true;
    if (uri.hasQuery) throw const FormatException('HTTP/SOCKS5 节点链接不支持查询参数');
  } else if (type == 'ss') {
    final credentials = uri.userInfo.contains(':') ? auth : _decode64(auth);
    final colon = credentials.indexOf(':');
    if (colon <= 0) throw const FormatException('SS 认证信息无效');
    final cipher = credentials.substring(0, colon);
    const ciphers = {
      'aes-128-gcm',
      'aes-192-gcm',
      'aes-256-gcm',
      'chacha20-ietf-poly1305',
      'xchacha20-ietf-poly1305',
      '2022-blake3-aes-128-gcm',
      '2022-blake3-aes-256-gcm',
      '2022-blake3-chacha20-poly1305',
      'aes-128-ctr',
      'aes-192-ctr',
      'aes-256-ctr',
      'aes-128-cfb',
      'aes-192-cfb',
      'aes-256-cfb',
      'chacha20-ietf',
      'chacha20',
      'xchacha20',
      'rc4-md5',
      'none',
      'aes-128-ccm',
      'aes-192-ccm',
      'aes-256-ccm',
      'aes-128-gcm-siv',
      'aes-256-gcm-siv',
      'chacha8-ietf-poly1305',
      'xchacha8-ietf-poly1305',
      'lea-128-gcm',
      'lea-192-gcm',
      'lea-256-gcm',
      'rabbit128-poly1305',
      'aegis-128l',
      'aegis-256',
      'aez-384',
      'deoxys-ii-256-128',
    };
    if (!ciphers.contains(cipher)) throw const FormatException('暂不支持此 SS 加密方法');
    node['cipher'] = cipher;
    node['password'] = _required(credentials.substring(colon + 1), '密码');
    node['udp'] = true;
    _ssPlugin(node, q.take(['plugin']));
  } else if (type == 'vless' || type == 'trojan') {
    node['udp'] = true;
    node[type == 'vless' ? 'uuid' : 'password'] =
        type == 'vless' ? _uuid(auth) : _required(auth, '密码');
    final security = q.take(['security'], type == 'vless' ? 'none' : 'tls');
    if (!['none', 'tls', 'reality'].contains(security) ||
        (type == 'trojan' && security == 'none')) {
      throw const FormatException('暂不支持此节点安全类型');
    }
    if (type == 'vless') {
      final encryption = q.take(['encryption'], 'none');
      if (encryption != 'none' && encryption.isNotEmpty) {
        throw const FormatException('暂不支持此 VLESS 加密类型');
      }
      node['tls'] = security != 'none';
    }
    if (security != 'none') {
      _tls(node, q, type == 'vless' ? 'servername' : 'sni');
    }
    if (security == 'reality') _reality(node, q);
    _transport(node, q);
    if (type == 'vless') {
      final flow = q.take(['flow']);
      if (flow.isNotEmpty) {
        if (flow != 'xtls-rprx-vision' ||
            security == 'none' ||
            node['network'] != 'tcp') {
          throw const FormatException('Vision 需要 TLS/Reality 和 TCP 传输');
        }
        node['flow'] = flow;
      }
      final packet = q.take(['packetEncoding', 'packet-encoding']);
      if (packet.isNotEmpty) {
        if (!['xudp', 'packetaddr'].contains(packet)) {
          throw const FormatException('VLESS UDP 编码无效');
        }
        node['packet-encoding'] = packet;
      }
    }
  } else {
    node['udp'] = true;
    if (type == 'anytls') {
      if (q.take(['security'], 'tls') != 'tls' ||
          q.take(['type', 'network'], 'tcp') != 'tcp') {
        throw const FormatException('AnyTLS 仅支持 TLS 和 TCP');
      }
    }
    _tls(node, q, 'sni', clientFingerprint: type == 'anytls');
    if (type == 'tuic') {
      final colon = uri.userInfo.indexOf(':');
      if (colon < 0) throw const FormatException('TUIC v5 需要 UUID 和密码');
      node['uuid'] =
          _uuid(Uri.decodeComponent(uri.userInfo.substring(0, colon)));
      node['password'] = _required(
          Uri.decodeComponent(uri.userInfo.substring(colon + 1)), '密码');
      final congestion =
          q.take(['congestion_control', 'congestion-controller']);
      if (congestion.isNotEmpty) {
        if (!['bbr', 'cubic', 'new_reno'].contains(congestion)) {
          throw const FormatException('TUIC 拥塞控制类型无效');
        }
        node['congestion-controller'] = congestion;
      }
      final relay = q.take(['udp_relay_mode', 'udp-relay-mode']);
      if (relay.isNotEmpty) {
        if (!['native', 'quic'].contains(relay)) {
          throw const FormatException('TUIC UDP 模式无效');
        }
        node['udp-relay-mode'] = relay;
      }
      for (final aliases in [
        ['disable_sni', 'disable-sni'],
        ['reduce_rtt', 'reduce-rtt']
      ]) {
        final value = q.flag(aliases);
        if (value != null) node[aliases.last] = value;
      }
    } else {
      node['password'] = _required(auth, '密码');
      if (type == 'hysteria2') {
        for (final key in ['up', 'down']) {
          final value = q.take([key]);
          if (value.isNotEmpty) {
            if (!RegExp(r'^\d+(\.\d+)?(\s*[KMG]?bps)?$', caseSensitive: false)
                .hasMatch(value)) {
              throw const FormatException('Hysteria2 带宽参数无效');
            }
            node[key] = value;
          }
        }
        final ports = q.take(['mport', 'ports']);
        if (ports.isNotEmpty) {
          for (final range in ports.split(',')) {
            final ends = range.split('-').map(int.tryParse).toList();
            if (ends.isEmpty ||
                ends.length > 2 ||
                ends.any((v) => v == null || v < 1 || v > 65535) ||
                (ends.length == 2 && ends.first! > ends.last!)) {
              throw const FormatException('Hysteria2 跳跃端口范围无效');
            }
          }
          node['ports'] = ports;
        }
        final obfs = q.take(['obfs']);
        final password = q.take(['obfs-password', 'obfsPassword']);
        if (obfs.isNotEmpty) {
          if (obfs != 'salamander') {
            throw const FormatException('暂不支持此 Hysteria2 混淆类型');
          }
          node['obfs'] = obfs;
          node['obfs-password'] = _required(password, '混淆密码');
        } else if (password.isNotEmpty) {
          throw const FormatException('Hysteria2 混淆密码需要 obfs 参数');
        }
      }
    }
  }
  q.finish();
  return node;
}
