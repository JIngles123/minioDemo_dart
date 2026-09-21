import 'dart:io';
import 'package:aws_s3_api/s3-2006-03-01.dart';

void main() async {
  // S3 client setup
  final s3 = S3(
    region: 'us-east-1',
    credentials: AwsClientCredentials(
      accessKey: 'jlmtest',
      secretKey: 'jlmtestpwd',
    ),
    // For a local MinIO server, also set:
    endpointUrl: 'http://localhost:9000',
  );

  // Run this demo from the minioDemo directory.
  final file = File('../minioTest.html'); // 待上传的本地文件名
  final bucketName = 'jlmtest';
  final key = 'minioTest.html'; // 待上传的minIO上的文件名

  try {
    // 将本地文件上传到minIO
    await s3.putObject(
      bucket: bucketName,
      key: key,
      body: await file.readAsBytes(), // 将本地文件内容读取为字节流
    );

    print('File uploaded successfully to $bucketName/$key');
  } catch (e) {
    print('Error uploading file: $e');
  } finally {
    s3.close();
  }
}
