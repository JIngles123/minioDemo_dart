import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';

/// Generates an S3 presigned GET URL for MinIO.
///
/// Signing happens locally — MinIO is not contacted until someone opens the URL.
void main() async {
  const endpointHost = 'localhost:9000';
  const bucketName = 'jlmtest';
  const key = 'minioTest.html';

  const credentials = AWSCredentials('jlmtest', 'jlmtestpwd');
  const signer = AWSSigV4Signer(
    credentialsProvider: AWSCredentialsProvider(credentials),
  );

  final signedUrl = await signer.presign(
    // MinIO uses path-style URLs: http://host/bucket/key
    AWSHttpRequest.get(
      Uri.http(endpointHost, '/$bucketName/$key'),
      headers: {
        AWSHeaders.host: endpointHost
      },
    ),
    credentialScope: AWSCredentialScope(
      region: 'us-east-1',
      service: AWSService.s3
    ),
    serviceConfiguration: S3ServiceConfiguration(),
    expiresIn: const Duration(minutes: 10), // 有效期 10 分钟
  );

  print('Presigned GET URL (valid 10 minutes):');
  print(signedUrl);
}
