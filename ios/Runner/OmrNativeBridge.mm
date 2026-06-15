#import "OmrNativeBridge.h"
#import <Foundation/Foundation.h>
#import <mach/mach.h>

#import <algorithm>
#import <cmath>
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
#import <opencv2/imgcodecs.hpp>
#import <opencv2/objdetect.hpp>

namespace {

constexpr int kOutputW = 595;
constexpr int kOutputH = 842;
constexpr double kCornerMarkerSize = 20.0;
constexpr double kTimingMarkSize = 6.0;
constexpr double kTimingSpacing = 80.0;
constexpr double kTimingEdge = 8.0;
constexpr double kMarginTop = 34.0;
constexpr double kBubbleD = 11.5;
constexpr double kBubbleBorder = 1.2;
constexpr double kDefaultFillThresh = 0.40;
constexpr int kOmrCols = 4;
constexpr int kOmrRows = 10;
constexpr double kOmrIdTop = 114.0;
constexpr double kOmrColSpc = 50.0;
constexpr double kOmrRowSpc = 12.0;
constexpr double kOmrFirstColX = 222.5;
constexpr double kOmrFirstRowY = 134.0;
constexpr double kCalY = 810.0;
constexpr double kCalFillX = 80.0;
constexpr double kCalEmptyX = 110.0;
constexpr int kAnswerOpts = 5;
constexpr double kAnsGridTop = 276.0;
constexpr double kAnsGridBot = 770.0;
constexpr double kAnsGridL = 28.0;
constexpr double kAnsGridR = 567.0;
constexpr double kQNumW = 16.0;
constexpr double kAnsInset = 6.0;
constexpr double kAnsGap = 6.0;
constexpr double kRowMarkX = 18.0;
constexpr double kRowMarkSz = 4.0;
constexpr double kMinBlur = 100.0;
constexpr double kMinContrastRatio = 1.5;
constexpr double kNoiseThresh = 15.0;

enum class ProcQ { High, Balanced, Fast };

struct Corners {
  cv::Point2f tl, tr, bl, br;
  bool valid(double w, double h) const {
    auto dist = [](cv::Point2f a, cv::Point2f b) {
      return std::hypot(a.x - b.x, a.y - b.y);
    };
    double w1 = dist(tl, tr), w2 = dist(bl, br);
    double h1 = dist(tl, bl), h2 = dist(tr, br);
    double wr = std::min(w1, w2) / std::max(w1, w2);
    double hr = std::min(h1, h2) / std::max(h1, h2);
    return wr > 0.8 && hr > 0.8;
  }
};

struct QrLayout {
  std::string templateId;
  int columns = 0;
  int rows = 0;
  double gridTop = kAnsGridTop;
  double gridBottom = kAnsGridBot;
  double rowHeight = 0;
  double columnWidth = 0;
  double bubbleSpacingX = 17.0;
};

double distancePt(cv::Point2f a, cv::Point2f b) {
  return std::hypot(a.x - b.x, a.y - b.y);
}

Corners *assignCorners(std::vector<cv::Point2f> &cand, double w, double h) {
  bool htl = false, htr = false, hbl = false, hbr = false;
  double btl = 1e9, btr = 1e9, bbl = 1e9, bbr = 1e9;
  cv::Point2f tl, tr, bl, br;
  for (auto &p : cand) {
    if (p.x < w * 0.3f && p.y < h * 0.3f) {
      double s = p.x + p.y;
      if (!htl || s < btl) { btl = s; tl = p; htl = true; }
    }
    if (p.x > w * 0.7f && p.y < h * 0.3f) {
      double s = (w - p.x) + p.y;
      if (!htr || s < btr) { btr = s; tr = p; htr = true; }
    }
    if (p.x < w * 0.3f && p.y > h * 0.7f) {
      double s = p.x + (h - p.y);
      if (!hbl || s < bbl) { bbl = s; bl = p; hbl = true; }
    }
    if (p.x > w * 0.7f && p.y > h * 0.7f) {
      double s = (w - p.x) + (h - p.y);
      if (!hbr || s < bbr) { bbr = s; br = p; hbr = true; }
    }
  }
  if (!htl || !htr || !hbl || !hbr) return nullptr;
  return new Corners{tl, tr, bl, br};
}

cv::Mat warpGray(const cv::Mat &gray, const Corners &c) {
  std::vector<cv::Point2f> src = {c.tl, c.tr, c.br, c.bl};
  std::vector<cv::Point2f> dst = {{0, 0}, {(float)kOutputW, 0}, {(float)kOutputW, (float)kOutputH}, {0, (float)kOutputH}};
  cv::Mat M = cv::getPerspectiveTransform(src, dst);
  cv::Mat out;
  cv::warpPerspective(gray, out, M, cv::Size(kOutputW, kOutputH));
  return out;
}

QrLayout fallbackLayout(int totalQ) {
  QrLayout L;
  L.templateId = "LEGACY";
  int cols, rows;
  double bsx;
  if (totalQ <= 30) { cols = 3; rows = 10; bsx = 26.0; }
  else if (totalQ <= 40) { cols = 4; rows = 10; bsx = 22.0; }
  else if (totalQ <= 50) { cols = 5; rows = 10; bsx = 17.0; }
  else if (totalQ <= 60) { cols = 5; rows = 12; bsx = 17.0; }
  else if (totalQ <= 70) { cols = 5; rows = 14; bsx = 17.0; }
  else if (totalQ <= 80) { cols = 5; rows = 16; bsx = 17.0; }
  else if (totalQ <= 90) { cols = 5; rows = 18; bsx = 17.0; }
  else { cols = 5; rows = 20; bsx = 17.0; }
  L.columns = cols;
  L.rows = rows;
  L.bubbleSpacingX = bsx;
  L.gridTop = kAnsGridTop;
  L.gridBottom = kAnsGridBot;
  double gh = kAnsGridBot - kAnsGridTop;
  double gw = kAnsGridR - kAnsGridL;
  L.rowHeight = gh / rows;
  L.columnWidth = gw / cols;
  return L;
}

QrLayout *parseQrLayout(NSString *qr) {
  if (!qr.length) return nullptr;
  NSData *d = [qr dataUsingEncoding:NSUTF8StringEncoding];
  NSError *err = nil;
  id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
  if (![obj isKindOfClass:[NSDictionary class]]) return nullptr;
  NSDictionary *root = obj;
  NSNumber *v = root[@"v"];
  if (v.intValue < 2) return nullptr;
  NSDictionary *lj = root[@"layout"];
  if (![lj isKindOfClass:[NSDictionary class]]) return nullptr;
  auto *L = new QrLayout();
  L->templateId = [lj[@"template"] isKindOfClass:[NSString class]] ? [(NSString *)lj[@"template"] UTF8String] : "";
  L->columns = [lj[@"cols"] intValue];
  L->rows = [lj[@"rows"] intValue];
  L->gridTop = [lj[@"gridTop"] doubleValue];
  if (L->gridTop == 0) L->gridTop = kAnsGridTop;
  L->gridBottom = [lj[@"gridBottom"] doubleValue];
  if (L->gridBottom == 0) L->gridBottom = kAnsGridBot;
  L->rowHeight = [lj[@"rowHeight"] doubleValue];
  L->columnWidth = [lj[@"colWidth"] doubleValue];
  L->bubbleSpacingX = [lj[@"bubbleSpacingX"] doubleValue];
  return L;
}

double sampleBubbleFillGray(const cv::Mat &g, double cx, double cy) {
  int r = (int)(kBubbleD / 2 + 2);
  int x = std::max(0, std::min((int)(cx - r), g.cols - r * 2));
  int y = std::max(0, std::min((int)(cy - r), g.rows - r * 2));
  cv::Rect roi(x, y, r * 2, r * 2);
  if (roi.width <= 0 || roi.height <= 0) return 0;
  cv::Scalar m = cv::mean(g(roi));
  return 1.0 - (m[0] / 255.0);
}

struct BubbleAn {
  double fill = 0;
};

BubbleAn analyzeBubble(const cv::Mat &th, const cv::Mat &gray, double cx, double cy) {
  int rad = (int)(kBubbleD / 2 + 1);
  int x = std::max(0, std::min((int)(cx - rad), th.cols - rad * 2 - 1));
  int y = std::max(0, std::min((int)(cy - rad), th.rows - rad * 2 - 1));
  int size = std::min(rad * 2, std::min(th.cols - x, th.rows - y));
  if (size <= 4) return {};
  cv::Rect R(x, y, size, size);
  cv::Mat troi = th(R), groi = gray(R);
  cv::Mat mask = cv::Mat::zeros(size, size, CV_8UC1);
  cv::circle(mask, cv::Point(size / 2, size / 2), (int)(size * 0.35), cv::Scalar(255), -1);
  cv::Mat masked;
  cv::bitwise_and(troi, mask, masked);
  double white = cv::countNonZero(masked);
  double mpx = cv::countNonZero(mask);
  double thFill = mpx > 0 ? white / mpx : 0;
  cv::Scalar meanI = cv::mean(groi, mask);
  double intFill = 1.0 - (meanI[0] / 255.0);
  BubbleAn a;
  a.fill = (thFill + intFill) / 2.0;
  return a;
}

bool checkTimingMark(const cv::Mat &bin, double x, double y) {
  int rad = (int)(kTimingMarkSize / 2 + 2);
  int cx = std::max(rad, std::min((int)x, bin.cols - rad - 1));
  int cy = std::max(rad, std::min((int)y, bin.rows - rad - 1));
  cv::Rect roi(cx - rad, cy - rad, rad * 2, rad * 2);
  cv::Mat patch = bin(roi);
  double nz = cv::countNonZero(patch);
  double tot = patch.rows * patch.cols;
  return (nz / tot) > 0.15;
}

double validateTimingMarks(const cv::Mat &warped) {
  cv::Mat bin;
  cv::threshold(warped, bin, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
  int found = 0, exp = 0;
  for (double x = 60; x < 535; x += kTimingSpacing) {
    exp++;
    if (checkTimingMark(bin, x, kTimingEdge)) found++;
  }
  for (double x = 60; x < 535; x += kTimingSpacing) {
    exp++;
    if (checkTimingMark(bin, x, kOutputH - kTimingEdge)) found++;
  }
  for (double y = 60; y < 780; y += kTimingSpacing) {
    exp++;
    if (checkTimingMark(bin, kTimingEdge, y)) found++;
  }
  for (double y = 60; y < 780; y += kTimingSpacing) {
    exp++;
    if (checkTimingMark(bin, kOutputW - kTimingEdge, y)) found++;
  }
  return exp > 0 ? (double)found / exp : 0;
}

Corners *detectBalanced(const cv::Mat &gray) {
  double w = gray.cols, h = gray.rows;
  cv::Mat blur, bin;
  cv::GaussianBlur(gray, blur, cv::Size(5, 5), 0);
  cv::threshold(blur, bin, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(bin, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
  double expected = (w * kCornerMarkerSize / kOutputW) * (h * kCornerMarkerSize / kOutputH);
  std::vector<cv::Point2f> cand;
  for (auto &c : contours) {
    double area = cv::contourArea(c);
    if (area < expected * 0.3 || area > expected * 4) continue;
    cv::Rect r = cv::boundingRect(c);
    double ar = (double)r.width / std::max(1, r.height);
    if (ar < 0.7 || ar > 1.4) continue;
    cand.push_back(cv::Point2f(r.x + r.width / 2.0f, r.y + r.height / 2.0f));
  }
  if (cand.size() < 4) return nullptr;
  return assignCorners(cand, w, h);
}

Corners *detectMultiThresh(const cv::Mat &gray) {
  double w = gray.cols, h = gray.rows;
  double expected = (w * kCornerMarkerSize / kOutputW) * (h * kCornerMarkerSize / kOutputH);
  for (double thr : {80.0, 100.0, 120.0, 140.0, 160.0}) {
    cv::Mat bin;
    cv::threshold(gray, bin, thr, 255, cv::THRESH_BINARY_INV);
    cv::Mat k = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
    cv::morphologyEx(bin, bin, cv::MORPH_CLOSE, k);
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(bin, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    std::vector<cv::Point2f> cand;
    for (auto &c : contours) {
      double area = cv::contourArea(c);
      if (area < expected * 0.2 || area > expected * 6) continue;
      cv::Rect r = cv::boundingRect(c);
      double ar = (double)r.width / std::max(1, r.height);
      if (ar < 0.5 || ar > 2.0) continue;
      cand.push_back(cv::Point2f(r.x + r.width / 2.0f, r.y + r.height / 2.0f));
    }
    if (cand.size() >= 4) {
      Corners *co = assignCorners(cand, w, h);
      if (co && co->valid(w, h)) return co;
      delete co;
    }
  }
  return nullptr;
}

Corners *detectEdge(const cv::Mat &gray) {
  double w = gray.cols, h = gray.rows;
  double expected = (w * kCornerMarkerSize / kOutputW) * (h * kCornerMarkerSize / kOutputH);
  cv::Mat edges;
  cv::Canny(gray, edges, 50, 150);
  cv::Mat k = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
  cv::dilate(edges, edges, k);
  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(edges, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
  std::vector<std::pair<cv::Point2f, double>> scored;
  for (auto &c : contours) {
    double area = cv::contourArea(c);
    if (area < expected * 0.1 || area > expected * 8) continue;
    cv::Rect r = cv::boundingRect(c);
    double ar = (double)r.width / std::max(1, r.height);
    if (ar < 0.4 || ar > 2.5) continue;
    double sq = 1.0 - std::abs(ar - 1.0);
    if (sq > 0.3)
      scored.push_back({cv::Point2f(r.x + r.width / 2.0f, r.y + r.height / 2.0f), area * sq});
  }
  std::sort(scored.begin(), scored.end(), [](auto &a, auto &b) { return a.second > b.second; });
  std::vector<cv::Point2f> cand;
  for (size_t i = 0; i < scored.size() && i < 8; i++) cand.push_back(scored[i].first);
  if (cand.size() < 4) return nullptr;
  return assignCorners(cand, w, h);
}

Corners *detectAdvanced(const cv::Mat &gray) {
  double w = gray.cols, h = gray.rows;
  cv::Mat filt, bin;
  cv::bilateralFilter(gray, filt, 9, 75, 75);
  cv::threshold(filt, bin, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
  std::vector<std::vector<cv::Point>> contours;
  std::vector<cv::Vec4i> hier;
  cv::findContours(bin, contours, hier, cv::RETR_TREE, cv::CHAIN_APPROX_SIMPLE);
  double expected = (w * kCornerMarkerSize / kOutputW) * (h * kCornerMarkerSize / kOutputH);
  std::vector<cv::Point2f> cand;
  for (int i = 0; i < (int)contours.size(); i++) {
    auto &c = contours[i];
    double area = cv::contourArea(c);
    if (area < expected * 0.2 || area > expected * 5) continue;
    cv::Rect r = cv::boundingRect(c);
    double ar = (double)r.width / std::max(1, r.height);
    if (ar < 0.7 || ar > 1.4) continue;
    int child = hier[i][2];
    if (child >= 0 && child < (int)contours.size()) {
      double ca = cv::contourArea(contours[child]);
      double ratio = ca / std::max(area, 1.0);
      if (ratio > 0.15 && ratio < 0.4)
        cand.push_back(cv::Point2f(r.x + r.width / 2.0f, r.y + r.height / 2.0f));
    }
  }
  if (cand.size() < 4) return nullptr;
  return assignCorners(cand, w, h);
}

Corners *detectFallback(const cv::Mat &gray) {
  double w = gray.cols, h = gray.rows;
  int ss = (int)(std::min(w, h) * 0.12);
  ss = std::max(ss, 20);
  std::vector<cv::Rect> regs = {
    {0, 0, ss, ss},
    {(int)(w - ss), 0, ss, ss},
    {0, (int)(h - ss), ss, ss},
    {(int)(w - ss), (int)(h - ss), ss, ss}
  };
  std::vector<cv::Point2f> pts;
  for (auto &reg : regs) {
    reg &= cv::Rect(0, 0, gray.cols, gray.rows);
    if (reg.width <= 0 || reg.height <= 0) return nullptr;
    cv::Mat roi = gray(reg);
    cv::Mat b;
    cv::threshold(roi, b, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(b, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    double best = 0;
    bool found = false;
    cv::Rect bestR;
    for (auto &c : contours) {
      double area = cv::contourArea(c);
      if (area < 50) continue;
      cv::Rect r = cv::boundingRect(c);
      double ar = (double)r.width / std::max(1, r.height);
      double sc = (1.0 - std::abs(ar - 1.0)) * std::min(area / 500.0, 1.0);
      if (sc > best) { best = sc; bestR = r; found = true; }
    }
    if (!found || best < 0.5) return nullptr;
    pts.push_back(cv::Point2f(reg.x + bestR.x + bestR.width / 2.0f, reg.y + bestR.y + bestR.height / 2.0f));
  }
  if (pts.size() != 4) return nullptr;
  return new Corners{pts[0], pts[1], pts[2], pts[3]};
}

Corners *detectCornersAdaptive(const cv::Mat &gray, ProcQ q) {
  double w = gray.cols, h = gray.rows;
  Corners *c = nullptr;
  if (q == ProcQ::Fast) c = detectFallback(gray);
  else if (q == ProcQ::Balanced) c = detectBalanced(gray);
  else c = detectAdvanced(gray);
  if (!c || !c->valid(w, h)) { delete c; c = detectMultiThresh(gray); }
  if (!c || !c->valid(w, h)) { delete c; c = detectEdge(gray); }
  if (!c || !c->valid(w, h)) { delete c; c = detectFallback(gray); }
  if (!c || !c->valid(w, h)) { delete c; c = nullptr; }
  return c;
}

void assessQuality(const cv::Mat &gray, double &blurVar, double &contrastScore, double &brightness, double &noise) {
  cv::Mat lap;
  cv::Laplacian(gray, lap, CV_64F);
  cv::Scalar m, s;
  cv::meanStdDev(lap, m, s);
  blurVar = s[0] * s[0];
  double mn, mx;
  cv::minMaxLoc(gray, &mn, &mx);
  contrastScore = (mx - mn) / 255.0;
  brightness = cv::mean(gray)[0];
  cv::Mat bl, df;
  cv::GaussianBlur(gray, bl, cv::Size(5, 5), 0);
  cv::absdiff(gray, bl, df);
  noise = cv::mean(df)[0];
}

NSString *detectQR(const cv::Mat &warped) {
  cv::QRCodeDetector qr;
  cv::Rect qrR((int)(kOutputW * 0.7), (int)kMarginTop, (int)(kOutputW * 0.25), 100);
  qrR &= cv::Rect(0, 0, warped.cols, warped.rows);
  cv::Mat roi = warped(qrR);
  std::string decoded = qr.detectAndDecode(roi);
  if (!decoded.empty()) return [NSString stringWithUTF8String:decoded.c_str()];
  decoded = qr.detectAndDecode(warped);
  if (!decoded.empty()) return [NSString stringWithUTF8String:decoded.c_str()];
  return nil;
}

NSDictionary *processCore(NSData *data, int totalQuestions, NSMutableDictionary *debug) {
  if (data.length == 0) return nil;
  std::vector<uchar> buf((uchar *)data.bytes, (uchar *)data.bytes + data.length);
  cv::Mat color = cv::imdecode(buf, cv::IMREAD_COLOR);
  if (color.empty()) return nil;
  cv::Mat gray;
  cv::cvtColor(color, gray, cv::COLOR_BGR2GRAY);
  int maxD = std::max(gray.cols, gray.rows);
  if (maxD > 1600) {
    double sc = 1600.0 / maxD;
    cv::resize(gray, gray, cv::Size(), sc, sc, cv::INTER_AREA);
  }
  debug[@"imageWidth"] = @(gray.cols);
  debug[@"imageHeight"] = @(gray.rows);
  double blurV, contrast, bright, noise;
  assessQuality(gray, blurV, contrast, bright, noise);
  debug[@"blurScore"] = @(blurV);
  debug[@"contrastScore"] = @(contrast);
  debug[@"brightnessScore"] = @(bright);
  debug[@"noiseScore"] = @(noise);
  ProcQ pq = ProcQ::High;
  debug[@"processingQuality"] = @"HIGH";
  Corners *corners = detectCornersAdaptive(gray, pq);
  if (!corners) {
    NSString *msg = @"Could not detect all 4 corner markers. Ensure the entire sheet is visible with good lighting.";
    if (blurV < kMinBlur * 0.3) msg = @"Image is too blurry. Hold your phone steady and tap to focus before capturing.";
    else if (bright < 50) msg = @"Image is too dark. Move to a brighter area or turn on a light.";
    else if (bright > 230) msg = @"Image is overexposed. Reduce lighting or avoid direct light on the sheet.";
    else if (contrast < 0.15) msg = @"Cannot distinguish the sheet. Ensure the paper is flat with even lighting.";
    NSDictionary *err = @{
      @"success": @NO,
      @"omrId": [NSNull null],
      @"answers": @{},
      @"confidence": @0,
      @"qrData": [NSNull null],
      @"errorMessage": msg,
      @"debugInfo": debug
    };
    return err;
  }
  debug[@"cornersDetected"] = @YES;
  cv::Mat warped = warpGray(gray, *corners);
  delete corners;
  debug[@"warpedSize"] = [NSString stringWithFormat:@"%dx%d", warped.cols, warped.rows];
  double timingScore = validateTimingMarks(warped);
  debug[@"timingMarkScore"] = @(timingScore);
  NSString *qrStr = detectQR(warped);
  debug[@"qrDetected"] = @(qrStr != nil);
  QrLayout *layout = parseQrLayout(qrStr);
  if (!layout) {
    layout = new QrLayout(fallbackLayout(totalQuestions));
    debug[@"layoutFromQr"] = @NO;
  } else {
    debug[@"layoutFromQr"] = @YES;
  }
  debug[@"layoutTemplate"] = [NSString stringWithUTF8String:layout->templateId.c_str()];
  double fillTh = kDefaultFillThresh;
  double ff = sampleBubbleFillGray(warped, kCalFillX, kCalY);
  double ef = sampleBubbleFillGray(warped, kCalEmptyX, kCalY);
  debug[@"calibrationFilledSample"] = @(ff);
  debug[@"calibrationEmptySample"] = @(ef);
  bool calibrated = ff > ef + 0.15;
  if (calibrated) fillTh = (ff + ef) / 2.0;
  debug[@"fillThreshold"] = @(fillTh);
  debug[@"calibrationSuccess"] = @(calibrated);
  cv::Mat th;
  cv::adaptiveThreshold(warped, th, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY_INV, 15, 4);
  NSMutableString *omr = [NSMutableString string];
  NSMutableArray *digitConf = [NSMutableArray array];
  bool omrOk = YES;
  for (int col = 0; col < kOmrCols && omrOk; col++) {
    double colX = kOmrFirstColX + col * kOmrColSpc;
    int bestD = -1;
    double bestF = 0, secondF = 0;
    for (int d = 0; d < kOmrRows; d++) {
      double y = kOmrFirstRowY + d * kOmrRowSpc;
      BubbleAn a = analyzeBubble(th, warped, colX, y);
      if (a.fill > bestF) { secondF = bestF; bestF = a.fill; bestD = d; }
      else if (a.fill > secondF) secondF = a.fill;
    }
    if (bestD < 0 || bestF <= fillTh) { omrOk = NO; break; }
    [omr appendFormat:@"%d", bestD];
    double sep = bestF - secondF;
    double conf = std::min(sep / 0.2, 1.0);
    [digitConf addObject:@(conf)];
  }
  if (!omrOk || omr.length != 4) {
    delete layout;
    NSDictionary *err = @{
      @"success": @NO,
      @"omrId": [NSNull null],
      @"answers": @{},
      @"confidence": @0,
      @"qrData": qrStr ?: [NSNull null],
      @"errorMessage": @"Could not read OMR ID. Ensure all 4 digits are clearly filled.",
      @"debugInfo": debug
    };
    return err;
  }
  while (omr.length < 4) [omr insertString:@"0" atIndex:0];
  debug[@"omrId"] = omr;
  NSMutableDictionary *answers = [NSMutableDictionary dictionary];
  NSMutableArray *qconf = [NSMutableArray array];
  int multi = 0, none = 0;
  NSMutableArray *ambig = [NSMutableArray array];
  const char *opts = "ABCDE";
  for (int qn = 1; qn <= totalQuestions; qn++) {
    int col = (qn - 1) / layout->rows;
    int row = (qn - 1) % layout->rows;
    if (col >= layout->columns) break;
    double rowY = layout->gridTop + row * layout->rowHeight + layout->rowHeight / 2.0;
    double bubbleAreaW = layout->bubbleSpacingX * (kAnswerOpts - 1);
    double usableW = layout->columnWidth - kAnsInset * 2;
    double rowContentW = kQNumW + kAnsGap + bubbleAreaW;
    double colLeft = kAnsGridL + col * layout->columnWidth;
    double rowContentL = colLeft + kAnsInset + (usableW - rowContentW) / 2.0;
    double bubbleLeft = rowContentL + kQNumW + kAnsGap;
    double bestF = 0, secondF = 0;
    int bestIdx = -1;
    int filledCnt = 0;
    NSMutableArray *fills = [NSMutableArray array];
    for (int oi = 0; oi < kAnswerOpts; oi++) {
      double bx = bubbleLeft + oi * layout->bubbleSpacingX;
      BubbleAn a = analyzeBubble(th, warped, bx, rowY);
      [fills addObject:@(a.fill)];
      if (a.fill > fillTh) filledCnt++;
      if (a.fill > bestF) { secondF = bestF; bestF = a.fill; bestIdx = oi; }
      else if (a.fill > secondF) secondF = a.fill;
    }
    if (filledCnt > 1) { multi++; [ambig addObject:@(qn)]; continue; }
    if (filledCnt == 0) none++;
    if (bestIdx >= 0 && bestF > fillTh) {
      NSString *letter = [NSString stringWithFormat:@"%c", opts[bestIdx]];
      answers[[NSString stringWithFormat:@"%d", qn]] = letter;
      double sep = bestF - secondF;
      [qconf addObject:@(std::min(sep / 0.15, 1.0))];
    }
  }
  debug[@"multipleSelectionsLayout"] = @(multi);
  debug[@"noSelectionsLayout"] = @(none);
  debug[@"ambiguousQuestions"] = ambig;
  double avgQ = 0;
  for (NSNumber *n in qconf) avgQ += n.doubleValue;
  if (qconf.count) avgQ /= qconf.count;
  double avgD = 0;
  for (NSNumber *n in digitConf) avgD += n.doubleValue;
  if (digitConf.count) avgD /= digitConf.count;
  double conf = 1.0;
  conf *= (0.7 + timingScore * 0.3);
  if (!calibrated) conf *= 0.9;
  conf *= (0.5 + avgD * 0.5);
  conf *= (0.5 + avgQ * 0.5);
  if (qrStr) conf = std::min(conf * 1.05, 1.0);
  delete layout;
  debug[@"answersDetected"] = @(answers.count);
  debug[@"answersConfidence"] = @(avgQ);
  return @{
    @"success": @YES,
    @"omrId": omr,
    @"answers": answers,
    @"confidence": @(conf),
    @"qrData": qrStr ?: [NSNull null],
    @"errorMessage": [NSNull null],
    @"debugInfo": debug
  };
}

NSString *jsonFromDict(NSDictionary *d) {
  NSError *e = nil;
  NSData *jd = [NSJSONSerialization dataWithJSONObject:d options:0 error:&e];
  if (!jd) return nil;
  return [[NSString alloc] initWithData:jd encoding:NSUTF8StringEncoding];
}

}  // namespace

@implementation OmrNativeBridge

+ (BOOL)isOpenCvReady {
  return YES;
}

+ (NSString *)processWithImageBytes:(NSData *)data totalQuestions:(NSInteger)totalQuestions {
  NSMutableDictionary *dbg = [NSMutableDictionary dictionary];
  NSDictionary *out = processCore(data, (int)totalQuestions, dbg);
  if (!out) {
    out = @{
      @"success": @NO,
      @"omrId": [NSNull null],
      @"answers": @{},
      @"confidence": @0,
      @"qrData": [NSNull null],
      @"errorMessage": @"Failed to decode image",
      @"debugInfo": dbg
    };
  }
  return jsonFromDict(out);
}

+ (NSString *)processImageBytesLegacy:(NSData *)data {
  return [self processWithImageBytes:data totalQuestions:50];
}

+ (NSDictionary<NSString *, id> *)detectSheet:(NSData *)data {
  if (data.length == 0) return @{@"sheetDetected": @NO, @"isAligned": @NO, @"hasGoodLighting": @NO, @"confidence": @0, @"hint": @"Invalid image"};
  std::vector<uchar> buf((uchar *)data.bytes, (uchar *)data.bytes + data.length);
  cv::Mat color = cv::imdecode(buf, cv::IMREAD_COLOR);
  if (color.empty()) return @{@"sheetDetected": @NO, @"isAligned": @NO, @"hasGoodLighting": @NO, @"confidence": @0, @"hint": @"Invalid image"};
  cv::Mat gray;
  cv::cvtColor(color, gray, cv::COLOR_BGR2GRAY);
  int maxD = std::max(gray.cols, gray.rows);
  if (maxD > 1200) {
    double sc = 1200.0 / maxD;
    cv::resize(gray, gray, cv::Size(), sc, sc, cv::INTER_AREA);
  }
  double blurV, contrast, bright, noise;
  assessQuality(gray, blurV, contrast, bright, noise);
  bool light = bright > 70 && bright < 220 && contrast >= 0.2;
  Corners *c = detectCornersAdaptive(gray, ProcQ::High);
  if (!c) {
    double conf = (std::min(bright / 255.0, 1.0) * 0.35 + std::min(contrast, 1.0) * 0.25 +
                   std::min(blurV / (kMinBlur * 2), 1.0) * 0.4);
    conf = std::min(conf, 0.55);
    NSString *hint = @"Position sheet in frame";
    if (bright < 60) hint = @"Improve lighting";
    else if (bright > 230) hint = @"Reduce glare";
    else if (blurV < kMinBlur * 0.6) hint = @"Hold steady";
    else if (contrast < 0.15) hint = @"Improve sheet contrast";
    return @{@"sheetDetected": @NO, @"isAligned": @NO, @"hasGoodLighting": @(light), @"confidence": @(conf), @"hint": hint};
  }
  double w = gray.cols, h = gray.rows;
  double topTilt = 1.0 - std::min(std::abs(c->tl.y - c->tr.y) / h, 1.0);
  double botTilt = 1.0 - std::min(std::abs(c->bl.y - c->br.y) / h, 1.0);
  double leftTilt = 1.0 - std::min(std::abs(c->tl.x - c->bl.x) / w, 1.0);
  double rightTilt = 1.0 - std::min(std::abs(c->tr.x - c->br.x) / w, 1.0);
  double minX = std::min(c->tl.x, c->bl.x), maxX = std::max(c->tr.x, c->br.x);
  double minY = std::min(c->tl.y, c->tr.y), maxY = std::max(c->bl.y, c->br.y);
  double cov = ((maxX - minX) / w + (maxY - minY) / h) / 2.0;
  cov = std::min(cov, 1.0);
  double align = ((topTilt + botTilt + leftTilt + rightTilt) / 4.0 * 0.65 + cov * 0.35);
  bool aligned = align >= 0.65;
  delete c;
  double conf = aligned && light ? std::min(0.65 + cov * 0.35, 1.0) : align * 0.8;
  NSString *hint = aligned ? (NSString *)nil : @"Align sheet edges with frame";
  NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:@{
    @"sheetDetected": @YES,
    @"isAligned": @(aligned),
    @"hasGoodLighting": @(light),
    @"confidence": @(conf)
  }];
  if (hint) m[@"hint"] = hint;
  return m;
}

+ (NSDictionary<NSString *, NSNumber *> *)analyzeImageQuality:(NSData *)data {
  if (data.length == 0) return nil;
  std::vector<uchar> buf((uchar *)data.bytes, (uchar *)data.bytes + data.length);
  cv::Mat color = cv::imdecode(buf, cv::IMREAD_COLOR);
  if (color.empty()) return nil;
  cv::Mat gray;
  cv::cvtColor(color, gray, cv::COLOR_BGR2GRAY);
  double blurV, contrast, bright, noise;
  assessQuality(gray, blurV, contrast, bright, noise);
  double sharp = std::min(blurV / 50.0, 1.0);
  return @{
    @"brightness": @(bright / 255.0),
    @"contrast": @(std::min(contrast * 3, 1.0)),
    @"sharpness": @(sharp)
  };
}

+ (NSDictionary<NSString *, id> *)deviceInfo {
  mach_task_basic_info_data_t info;
  mach_msg_type_number_t cnt = MACH_TASK_BASIC_INFO_COUNT;
  kern_return_t kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &cnt);
  int64_t resident = (kr == KERN_SUCCESS) ? (int64_t)info.resident_size : 0;
  return @{
    @"freeMemoryMB": @0,
    @"maxMemoryMB": @512,
    @"totalMemoryMB": @(resident / (1024 * 1024)),
    @"processorCount": @((int)NSProcessInfo.processInfo.processorCount),
    @"isProcessing": @NO
  };
}

@end
