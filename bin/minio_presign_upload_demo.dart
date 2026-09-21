import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aws_common/aws_common.dart';
import 'package:aws_s3_api/s3-2006-03-01.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';

void main(List<String> arguments) async {
  const region = 'us-east-1';
  const endpointHost = 'localhost:9000';
  const bucketName = 'jlmtest';
  const expiresIn = Duration(minutes: 10);
  const singlePutMaxBytes = 1 * 1024 * 1024;
  const partSizeBytes = 5 * 1024 * 1024;

  // $ dart run bin/minio_presign_upload_demo.dart /home/jlm/Applications/Investigation/mdnsresponderTEST/native-lib.zip  native-lib.zip
  final file = File(arguments.isEmpty ? '../minioTest.html' : arguments.first);
  if (!file.existsSync()) {
    throw StateError('File not found: ${file.path}');
  }
  final key = arguments.length > 1 ? arguments[1] : 'uploadTest.tmp';
  final fileSize = await file.length();

  const credentials = AWSCredentials('jlmtest', 'jlmtestpwd');
  const signer = AWSSigV4Signer(
    credentialsProvider: AWSCredentialsProvider(credentials),
  );
  final scope = AWSCredentialScope(region: region, service: AWSService.s3);
  final serviceConfiguration = S3ServiceConfiguration();

  final s3 = S3(
    region: region,
    credentials: AwsClientCredentials(
      accessKey: credentials.accessKeyId,
      secretKey: credentials.secretAccessKey,
    ),
    endpointUrl: 'http://$endpointHost',
  );

  print('Local file: ${file.path} ($fileSize bytes)');
  print('Destination: $bucketName/$key');

  try {
    // 如果文件大小 <= 1 MB，则使用单次 PUT 上传
    if (fileSize <= singlePutMaxBytes) {
      await _uploadWholeFile(
        signer: signer, // 签名器
        scope: scope, // 凭证范围
        serviceConfiguration: serviceConfiguration, // 服务配置
        endpointHost: endpointHost, // 端点主机
        bucketName: bucketName, // 桶名
        key: key, // 对象键
        file: file, // 文件
        expiresIn: expiresIn, // 有效期
      );
    } else {
      await _uploadMultipart(
        s3: s3,
        signer: signer,
        scope: scope,
        serviceConfiguration: serviceConfiguration,
        endpointHost: endpointHost,
        bucketName: bucketName,
        key: key,
        file: file,
        fileSize: fileSize,
        partSizeBytes: partSizeBytes,
        expiresIn: expiresIn,
      );
    }
    print('Upload finished: $bucketName/$key');
  } finally {
    s3.close();
  }
}

Future<void> _uploadWholeFile({
  required AWSSigV4Signer signer,
  required AWSCredentialScope scope,
  required S3ServiceConfiguration serviceConfiguration,
  required String endpointHost,
  required String bucketName,
  required String key,
  required File file,
  required Duration expiresIn,
}) async {
  print('Mode: single PUT (file <= 1 MiB)');
  final signedUrl = await _presignPut(
    signer: signer,
    scope: scope,
    serviceConfiguration: serviceConfiguration,
    endpointHost: endpointHost,
    bucketName: bucketName,
    key: key,
    expiresIn: expiresIn,
  );
  print('Presigned PUT URL (valid ${expiresIn.inMinutes} minutes):');
  print(signedUrl);

  final result = await _putBytes(signedUrl, await file.readAsBytes());
  print('PUT status: ${result.statusCode} ETag: ${result.eTag}');
}

Future<void> _uploadMultipart({
  required S3 s3,
  required AWSSigV4Signer signer,
  required AWSCredentialScope scope,
  required S3ServiceConfiguration serviceConfiguration,
  required String endpointHost,
  required String bucketName,
  required String key,
  required File file,
  required int fileSize,
  required int partSizeBytes,
  required Duration expiresIn,
}) async {
  final partCount = (fileSize + partSizeBytes - 1) ~/ partSizeBytes;
  print('Mode: multipart ($partCount part(s), part size $partSizeBytes bytes)');

  // 开一个multipart上传会话，返回uploadId，POST?uploads
  final created = await s3.createMultipartUpload(bucket: bucketName, key: key);
  final uploadId = created.uploadId;
  if (uploadId == null || uploadId.isEmpty) {
    throw StateError('createMultipartUpload did not return uploadId');
  }
  print('uploadId: $uploadId');

  final completedParts = <CompletedPart>[];
  final raf = await file.open();
  try {
    var offset = 0;
    var partNumber = 1;
    while (offset < fileSize) {
      final length = min(partSizeBytes, fileSize - offset);
      final bytes = await raf.read(length);
      final signedUrl = await _presignPut(
        signer: signer,
        scope: scope,
        serviceConfiguration: serviceConfiguration,
        endpointHost: endpointHost,
        bucketName: bucketName,
        key: key,
        expiresIn: expiresIn,
        queryParameters: {'partNumber': '$partNumber', 'uploadId': uploadId},
      );
      print(
        'Presigned PUT URL for part $partNumber '
        '($length bytes, valid ${expiresIn.inMinutes} minutes):',
      );
      print(signedUrl);

      // 每片独立上传，响应里带ETag, PUT?partNumber=&uploadId=xxx
      final result = await _putBytes(signedUrl, bytes);
      completedParts.add(
        CompletedPart(eTag: result.eTag, partNumber: partNumber),
      );
      print(
        'Part $partNumber status: ${result.statusCode} ETag: ${result.eTag}',
      );

      offset += length;
      partNumber++;
    }

    // 收尾，提交各个片的ETag，服务器才回去拼成最终对象 bucketName/key，POST?uploadId=+各片清单
    await s3.completeMultipartUpload(
      bucket: bucketName,
      key: key,
      uploadId: uploadId,
      multipartUpload: CompletedMultipartUpload(parts: completedParts),
    );
  } catch (e) {
    // 失败，丢弃未完成的分片上传，避免占用存储空间，DELETE?uploadId=xx
    await s3.abortMultipartUpload(
      bucket: bucketName,
      key: key,
      uploadId: uploadId,
    );
    print('Multipart upload aborted: $e');
    rethrow;
  } finally {
    await raf.close();
  }
}

Future<Uri> _presignPut({
  required AWSSigV4Signer signer,
  required AWSCredentialScope scope,
  required S3ServiceConfiguration serviceConfiguration,
  required String endpointHost,
  required String bucketName,
  required String key,
  required Duration expiresIn,
  Map<String, String>? queryParameters,
}) {
  final request = AWSHttpRequest.put(
    Uri.http(endpointHost, '/$bucketName/$key', queryParameters),
    headers: {AWSHeaders.host: endpointHost},
  );
  return signer.presign(
    request,
    credentialScope: scope,
    serviceConfiguration: serviceConfiguration,
    expiresIn: expiresIn,
  );
}

Future<({int statusCode, String eTag})> _putBytes(
  Uri url,
  Uint8List bytes,
) async {
  final client = HttpClient();
  try {
    final request = await client.putUrl(url);
    request.headers.removeAll(HttpHeaders.contentTypeHeader);
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      throw StateError('PUT failed (${response.statusCode}): $body');
    }
    return (
      statusCode: response.statusCode,
      eTag: response.headers.value(HttpHeaders.etagHeader) ?? '',
    );
  } finally {
    client.close();
  }
}
