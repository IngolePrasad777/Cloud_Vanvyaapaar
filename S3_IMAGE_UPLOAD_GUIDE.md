# 📸 S3 Image Upload & CloudFront Integration Guide

## 🎯 Overview

Your infrastructure automatically creates:
1. **S3 Bucket**: `vanvyaapaar-prod-media-assets-{AWS_ACCOUNT_ID}`
2. **CloudFront Distribution**: For fast global image delivery
3. **IAM Permissions**: EC2 instances can upload to S3

---

## 📦 How Images Are Stored

### **S3 Bucket Structure**
```
vanvyaapaar-prod-media-assets-123456789012/
├── products/
│   ├── product-1.jpg
│   ├── product-2.jpg
│   └── product-3.jpg
├── sellers/
│   ├── seller-avatar-1.jpg
│   └── seller-avatar-2.jpg
└── categories/
    ├── pottery.jpg
    └── textiles.jpg
```

### **CloudFront URLs**
```
S3 URL (Direct):
https://vanvyaapaar-prod-media-assets-123456789012.s3.amazonaws.com/products/product-1.jpg

CloudFront URL (CDN - Use This):
https://d1234567890abc.cloudfront.net/products/product-1.jpg
```

---

## 🚀 OPTION 1: Manual Upload via AWS CLI

### **Upload Single Image**
```bash
# Get bucket name from CloudFormation outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name vanvyaapaar-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`MediaBucketName`].OutputValue' \
  --output text)

# Upload image
aws s3 cp my-product.jpg s3://$BUCKET_NAME/products/my-product.jpg \
  --content-type image/jpeg

# Get CloudFront URL
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
  --stack-name vanvyaapaar-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text)

echo "Image URL: $CLOUDFRONT_URL/products/my-product.jpg"
```

### **Upload Multiple Images**
```bash
# Upload all images from a folder
aws s3 sync ./product-images/ s3://$BUCKET_NAME/products/ \
  --exclude "*" \
  --include "*.jpg" \
  --include "*.png" \
  --content-type image/jpeg
```

---

## 🔧 OPTION 2: Upload from Backend EC2 Instance

### **SSH to Backend Instance**
```bash
BACKEND_INSTANCE=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=*Backend*" \
           "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ssh -i vanvyaapaar-key.pem ec2-user@$BACKEND_INSTANCE
```

### **Upload from EC2**
```bash
# Get bucket name (already has IAM permissions)
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name vanvyaapaar-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`MediaBucketName`].OutputValue' \
  --output text \
  --region us-east-1)

# Upload image
aws s3 cp /path/to/image.jpg s3://$BUCKET_NAME/products/image.jpg
```

---

## 💻 OPTION 3: Programmatic Upload (Java Backend)

### **Add AWS SDK to pom.xml**
```xml
<dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>s3</artifactId>
    <version>2.20.0</version>
</dependency>
```

### **Create S3 Upload Service**
```java
package com.tribal.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.io.IOException;
import java.util.UUID;

@Service
public class S3Service {

    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    @Value("${aws.cloudfront.url}")
    private String cloudFrontUrl;

    private final S3Client s3Client;

    public S3Service() {
        this.s3Client = S3Client.builder().build();
    }

    public String uploadProductImage(MultipartFile file) throws IOException {
        String fileName = "products/" + UUID.randomUUID() + "-" + file.getOriginalFilename();
        
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(fileName)
                .contentType(file.getContentType())
                .build();

        s3Client.putObject(putObjectRequest, 
                RequestBody.fromInputStream(file.getInputStream(), file.getSize()));

        return cloudFrontUrl + "/" + fileName;
    }

    public void deleteImage(String imageUrl) {
        String key = imageUrl.replace(cloudFrontUrl + "/", "");
        s3Client.deleteObject(builder -> builder.bucket(bucketName).key(key));
    }
}
```

### **Add to application.properties**
```properties
# Get these from CloudFormation outputs
aws.s3.bucket-name=${S3_BUCKET_NAME}
aws.cloudfront.url=${CLOUDFRONT_URL}
```

### **Create Upload Controller**
```java
package com.tribal.controller;

import com.tribal.service.S3Service;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/upload")
@CrossOrigin(origins = "*")
public class UploadController {

    @Autowired
    private S3Service s3Service;

    @PostMapping("/product-image")
    public ResponseEntity<?> uploadProductImage(@RequestParam("file") MultipartFile file) {
        try {
            String imageUrl = s3Service.uploadProductImage(file);
            Map<String, String> response = new HashMap<>();
            response.put("imageUrl", imageUrl);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Upload failed: " + e.getMessage());
        }
    }
}
```

---

## 🌐 OPTION 4: Frontend Direct Upload (React)

### **Install AWS SDK**
```bash
cd vanvyapaar-frontend
npm install @aws-sdk/client-s3 @aws-sdk/s3-request-presigner
```

### **Create Upload Component**
```typescript
// src/components/ImageUpload.tsx
import { useState } from 'react'
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3'

const s3Client = new S3Client({
  region: 'us-east-1',
  credentials: {
    accessKeyId: process.env.VITE_AWS_ACCESS_KEY_ID!,
    secretAccessKey: process.env.VITE_AWS_SECRET_ACCESS_KEY!,
  },
})

export function ImageUpload({ onUploadComplete }: { onUploadComplete: (url: string) => void }) {
  const [uploading, setUploading] = useState(false)

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    setUploading(true)
    try {
      const fileName = `products/${Date.now()}-${file.name}`
      const command = new PutObjectCommand({
        Bucket: process.env.VITE_S3_BUCKET_NAME,
        Key: fileName,
        Body: file,
        ContentType: file.type,
      })

      await s3Client.send(command)
      const imageUrl = `${process.env.VITE_CLOUDFRONT_URL}/${fileName}`
      onUploadComplete(imageUrl)
    } catch (error) {
      console.error('Upload failed:', error)
    } finally {
      setUploading(false)
    }
  }

  return (
    <div>
      <input type="file" accept="image/*" onChange={handleUpload} disabled={uploading} />
      {uploading && <p>Uploading...</p>}
    </div>
  )
}
```

---

## 🔐 Security: Presigned URLs (Recommended)

### **Backend: Generate Presigned URL**
```java
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;
import java.time.Duration;

@Service
public class S3Service {
    
    public String generatePresignedUploadUrl(String fileName) {
        S3Presigner presigner = S3Presigner.create();
        
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key("products/" + fileName)
                .build();

        PutObjectPresignRequest presignRequest = PutObjectPresignRequest.builder()
                .signatureDuration(Duration.ofMinutes(10))
                .putObjectRequest(putObjectRequest)
                .build();

        return presigner.presignPutObject(presignRequest).url().toString();
    }
}
```

### **Frontend: Upload to Presigned URL**
```typescript
// Get presigned URL from backend
const response = await api.post('/api/upload/presigned-url', {
  fileName: file.name,
  contentType: file.type,
})

const presignedUrl = response.data.url

// Upload directly to S3
await fetch(presignedUrl, {
  method: 'PUT',
  body: file,
  headers: {
    'Content-Type': file.type,
  },
})
```

---

## 📝 Update Product with Image URL

### **When Adding Product**
```typescript
// Frontend: src/pages/seller/AddProduct.tsx
const handleSubmit = async (data: ProductFormData) => {
  // 1. Upload image first
  const imageUrl = await uploadImage(data.imageFile)
  
  // 2. Create product with image URL
  const product = {
    ...data,
    imageUrl: imageUrl, // CloudFront URL
  }
  
  await sellerService.addProduct(sellerId, product)
}
```

### **Backend: Save Image URL**
```java
// Product entity already has imageUrl field
@Column(length = 500)
private String imageUrl;

// When creating product
Product product = Product.builder()
    .name(request.getName())
    .description(request.getDescription())
    .imageUrl(request.getImageUrl()) // CloudFront URL
    .build();
```

---

## 🎨 Display Images in Frontend

### **Product Card Component**
```typescript
// src/components/ProductCard.tsx
export function ProductCard({ product }: { product: Product }) {
  return (
    <div className="product-card">
      <img 
        src={product.imageUrl || '/placeholder.jpg'} 
        alt={product.name}
        onError={(e) => {
          e.currentTarget.src = '/placeholder.jpg'
        }}
      />
      <h3>{product.name}</h3>
      <p>₹{product.price}</p>
    </div>
  )
}
```

---

## 🔄 Migrate Existing Images

### **If you have images with Unsplash URLs**
```bash
# Script to download and re-upload to S3
#!/bin/bash

# Get products with Unsplash URLs
mysql -h $RDS_ENDPOINT -u admin -p vanvyaapaar -e \
  "SELECT id, image_url FROM products WHERE image_url LIKE '%unsplash%'" \
  > products.txt

# For each product
while read -r id url; do
  # Download image
  wget -O temp.jpg "$url"
  
  # Upload to S3
  aws s3 cp temp.jpg s3://$BUCKET_NAME/products/product-$id.jpg
  
  # Update database
  NEW_URL="$CLOUDFRONT_URL/products/product-$id.jpg"
  mysql -h $RDS_ENDPOINT -u admin -p vanvyaapaar -e \
    "UPDATE products SET image_url='$NEW_URL' WHERE id=$id"
  
  rm temp.jpg
done < products.txt
```

---

## 📊 Monitor S3 Usage

### **Check Bucket Size**
```bash
aws s3 ls s3://$BUCKET_NAME --recursive --summarize | grep "Total Size"
```

### **List All Images**
```bash
aws s3 ls s3://$BUCKET_NAME/products/ --recursive
```

### **CloudFront Cache Statistics**
```bash
aws cloudfront get-distribution-config \
  --id <DISTRIBUTION_ID> \
  --query 'DistributionConfig.CacheBehaviors'
```

---

## 🧹 Cleanup Old Images

### **Delete Unused Images**
```bash
# List all images in S3
aws s3 ls s3://$BUCKET_NAME/products/ --recursive > s3-images.txt

# Get all image URLs from database
mysql -h $RDS_ENDPOINT -u admin -p vanvyaapaar -e \
  "SELECT image_url FROM products" > db-images.txt

# Find images in S3 but not in database (unused)
# Then delete them
aws s3 rm s3://$BUCKET_NAME/products/unused-image.jpg
```

---

## ✅ Best Practices

1. **Use CloudFront URLs** (not direct S3 URLs) for faster delivery
2. **Optimize images** before upload (compress, resize)
3. **Use consistent naming**: `products/{product-id}-{timestamp}.jpg`
4. **Set proper Content-Type** when uploading
5. **Enable S3 versioning** for backup
6. **Use presigned URLs** for secure uploads
7. **Implement image validation** (size, format, dimensions)
8. **Add loading placeholders** in frontend
9. **Handle upload errors** gracefully
10. **Monitor S3 costs** (storage + data transfer)

---

## 🎯 Quick Start

```bash
# 1. Get bucket name and CloudFront URL
aws cloudformation describe-stacks \
  --stack-name vanvyaapaar-prod \
  --query 'Stacks[0].Outputs' \
  --output table

# 2. Upload test image
aws s3 cp test.jpg s3://vanvyaapaar-prod-media-assets-123456789012/products/test.jpg

# 3. Access via CloudFront
# https://d1234567890abc.cloudfront.net/products/test.jpg

# 4. Update product in database
mysql -h <RDS_ENDPOINT> -u admin -p vanvyaapaar
UPDATE products 
SET image_url = 'https://d1234567890abc.cloudfront.net/products/test.jpg' 
WHERE id = 1;
```

---

**Your S3 + CloudFront setup is ready!** 🎉

Images will be:
- ✅ Stored securely in S3
- ✅ Delivered fast via CloudFront CDN
- ✅ Accessible globally with low latency
- ✅ Cost-effective (free tier eligible)
