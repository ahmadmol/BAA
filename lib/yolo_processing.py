from flask import Flask, request, jsonify # type: ignore
from ultralytics import YOLO
import cv2
import numpy as np
import os

app = Flask(__name__)

model = YOLO("yolov8n.pt")  # تحميل النموذج

@app.route('/predict', methods=['POST'])
def predict():
    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 400
    
    file = request.files['image']
    img_bytes = file.read()

    # تحويل البايت إلى صورة OpenCV
    nparr = np.frombuffer(img_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    if img is None:
        return jsonify({'error': 'Invalid image'}), 400

    results = model(img)

    detections = []
    for r in results:
        for box in r.boxes:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            conf = float(box.conf[0])
            cls = int(box.cls[0])
            label = model.names[cls]
            detections.append({
                'label': label,
                'confidence': conf,
                'bbox': [x1, y1, x2, y2],
            })

    return jsonify({'detections': detections})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
