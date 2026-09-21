import 'dart:io';
import 'package:aws_s3_api/s3-2006-03-01.dart';

void main() async {
  final s3 = S3(
    region: 'us-east-1',
    credentials: AwsClientCredentials(
      accessKey: 'jlmtest',
      secretKey: 'jlmtestpwd',
    ),
    endpointUrl: 'http://localhost:9000',
  );

  final bucketName = 'jlmtest';
  // Download the same object created by minio_upload_demo.dart so the demo can
  // finish with a byte-for-byte comparison.
  final key = 'minioTest.html'; // 待下载的 minIO 上的文件名
  final output = File('downloaded_minioTest.html'); // 下载到本地的文件名
  try {
    // 拿到 minIO 上的文件
    final response = await s3.getObject(bucket: bucketName, key: key);
    final body = response.body;
    if (body == null) {
      throw StateError('Downloaded object has an empty body: $bucketName/$key');
    }

    // 将文件内容写入本地文件
    await output.writeAsBytes(body);
    print('File downloaded successfully to ${output.path}');
  } catch (e) {
    print('Error downloading file: $e');
  } finally {
    s3.close();
  }
}
