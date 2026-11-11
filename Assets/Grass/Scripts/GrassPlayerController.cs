using UnityEngine;

// ============================================================================
//  GrassPlayerController —— 测试用的第三人称角色控制器
//
//  操作方式（类似原神 / 绝大多数第三人称游戏）：
//    鼠标    环绕相机（上下看 / 左右转）
//    WASD    相对相机方向移动（W 永远是"镜头前方"）
//    Shift   冲刺
//    Esc     解锁鼠标；点击画面重新锁定
//
//  相机逻辑：
//    · 相机绕着角色转，不让角色去追相机
//    · 角色只在移动时朝移动方向转身（站着不动保持朝向）
//    · 相机与角色之间有遮挡检测，避免穿进地形
//
//  纯粹为了验证草地交互，换成正式角色时删掉这个组件，
//  把 GrassTrailEmitter 挂到角色上即可，草地系统不用改。
// ============================================================================

[RequireComponent(typeof(CharacterController))]
[AddComponentMenu("草地/Grass Player Controller (测试用)")]
public class GrassPlayerController : MonoBehaviour
{
    [Header("移动")]
    public float moveSpeed = 3.5f;
    public float sprintMultiplier = 2.2f;
    [Tooltip("转身速度（度/秒）")]
    public float turnSpeed = 720f;
    public float gravity = -18f;
    [Tooltip("起步加速度（米/秒²）。越大越跟手；6 ≈ 0.2 秒到满速")]
    public float acceleration = 6f;
    [Tooltip("松手后的减速度（米/秒²）。越大停得越干脆")]
    public float deceleration = 10f;

    [Header("相机：环绕")]
    public bool cameraFollow = true;
    [Tooltip("相机离角色多远")]
    public float cameraDistance = 4.5f;
    [Tooltip("镜头对准的角色高度（腰部偏上）")]
    public float cameraTargetHeight = 1.25f;
    [Tooltip("鼠标灵敏度")]
    public float mouseSensitivity = 4.0f;
    [Tooltip("竖直视角下限（正数=往下看）")]
    public float minPitch = -30f;
    [Tooltip("竖直视角上限")]
    public float maxPitch = 65f;
    [Tooltip("相机跟随的平滑速度")]
    public float cameraSmooth = 14f;
    [Tooltip("鼠标控制相机时锁定光标（Esc 解除）")]
    public bool lockCursor = true;
    [Tooltip("相机与角色之间做遮挡检测，防止穿地形")]
    public bool cameraCollision = true;

    [Header("动画")]
    [Tooltip("角色模型上的 Animator（留空则不动画）")]
    public Animator animator;
    [Tooltip("animator.speed = 1 对应的移动速度（米/秒）。走路动作的播放速度按这个换算")]
    public float walkRefSpeed = 2.7f;
    [Tooltip("Animator 里的浮点参数名（BlendTree 用）。留空或参数不存在时，退化为直接调整 animator.speed")]
    public string speedParameterName = "Speed";

    [Header("模型脚底对齐")]
    [Tooltip("手动微调：正数把模型抬高、负数下沉（米）。\n" +
             "模型比地面高就调成负数，陷进地里就调成正数。")]
    public float feetOffsetY = 0f;

    [Tooltip("模型局部 Y 的基准值（右键组件 →「以当前高度为基准」可重置）")]
    public float modelBaseY = 0f;
    [Tooltip("运行时是否自动按包围盒对齐脚底（包围盒通常比实际网格大，建议关掉手动调）")]
    public bool autoAlignFeet = false;

    [Header("调试")]
    [Tooltip("不用手动操作，自己一直往前走（用来看拖尾效果）")]
    public bool autoWalk = false;

    CharacterController _cc;
    Transform _cam;
    float _verticalVelocity;
    Vector3 _lastPos;
    float _planarSpeed;
    bool _hasSpeedParam;
    float _currentSpeed;   // 带阻尼后的实际移动速度
    Vector3 _moveDir;      // 最近一次的移动方向（松手后靠它滑行减速）

    // 相机环绕角度：yaw 绕 Y 轴，pitch 抬头/低头
    float _yaw;
    float _pitch = 14f;

    void Awake()
    {
        _cc = GetComponent<CharacterController>();
    }

    void Start()
    {
        if (cameraFollow && Camera.main != null) _cam = Camera.main.transform;
        _lastPos = transform.position;
        _hasSpeedParam = HasFloatParameter(animator, speedParameterName);

        // 相机初始朝向 = 角色朝向，这样进游戏不会突然跳一下
        _yaw = transform.eulerAngles.y;

        if (lockCursor) SetCursorLocked(true);

        // 模型脚底基准：取场景里当前摆好的位置
        if (modelBaseY == 0f && animator != null && animator.transform != transform)
            modelBaseY = animator.transform.localPosition.y;

        ApplyFeetOffset();
    }

    /// <summary>把 feetOffsetY 应用到模型上（幂等，编辑器里拖动滑块就能实时看到）。</summary>
    void ApplyFeetOffset()
    {
        if (animator == null || animator.transform == transform) return;
        var lp = animator.transform.localPosition;
        lp.y = modelBaseY + feetOffsetY;
        if (Mathf.Abs(animator.transform.localPosition.y - lp.y) > 1e-5f)
            animator.transform.localPosition = lp;
    }

    void OnValidate()
    {
        ApplyFeetOffset();
    }

    [ContextMenu("以当前高度为基准（清零偏移）")]
    void CaptureBaseY()
    {
        if (animator == null) return;
        modelBaseY = animator.transform.localPosition.y;
        feetOffsetY = 0f;
        Debug.Log($"[角色] 基准高度已记录: {modelBaseY:F3}");
    }

    [ContextMenu("按骨骼自动对齐脚底")]
    void AutoAlignFeet()
    {
        if (animator == null) return;
        var smr = animator.GetComponentInChildren<SkinnedMeshRenderer>();
        var cc = GetComponent<CharacterController>();
        if (smr == null || cc == null) return;

        // ⚠ 不能用 SkinnedMeshRenderer.bounds：它是保守包围盒，实测比真实网格低 0.4m，
        //   按它对齐会让角色悬空。改用脚部骨骼（foot / toe / ankle）的最低点。
        float lowest = float.MaxValue;
        string lowestName = null;
        if (smr.bones != null)
        {
            foreach (var b in smr.bones)
            {
                if (b == null) continue;
                string n = b.name.ToLowerInvariant();
                if (n.Contains("toe") || n.Contains("foot") || n.Contains("ankle"))
                {
                    if (b.position.y < lowest) { lowest = b.position.y; lowestName = b.name; }
                }
            }
        }
        if (lowestName == null)
        {
            Debug.LogWarning("[角色] 找不到脚部骨骼，请手动调 feetOffsetY");
            return;
        }

        float ccBottom = transform.position.y + cc.center.y - cc.height * 0.5f;
        modelBaseY = animator.transform.localPosition.y;
        feetOffsetY = ccBottom - lowest;
        ApplyFeetOffset();
        Debug.Log($"[角色] 按骨骼对齐: 最低脚部骨骼 '{lowestName}' y={lowest:F3}，偏移 {feetOffsetY:F3} m");
    }

    void OnDisable()
    {
        if (lockCursor) SetCursorLocked(false);
    }

    static void SetCursorLocked(bool locked)
    {
        Cursor.lockState = locked ? CursorLockMode.Locked : CursorLockMode.None;
        Cursor.visible = !locked;
    }

    /// <summary>判断 Animator 上是否存在指定名字的 Float 参数。</summary>
    static bool HasFloatParameter(Animator a, string paramName)
    {
        if (a == null || string.IsNullOrEmpty(paramName) || a.runtimeAnimatorController == null) return false;
        foreach (var p in a.parameters)
            if (p.type == AnimatorControllerParameterType.Float && p.name == paramName) return true;
        return false;
    }

    void Update()
    {
        // ── 鼠标：环绕相机 ──────────────────────────────────────────────
        if (lockCursor)
        {
            if (Input.GetKeyDown(KeyCode.Escape)) SetCursorLocked(false);
            else if (Input.GetMouseButtonDown(0) && Cursor.lockState != CursorLockMode.Locked)
                SetCursorLocked(true);
        }

        if (Cursor.lockState == CursorLockMode.Locked)
        {
            // 鼠标的 GetAxis 本身就是「这一帧移动了多少像素」，不要再乘 deltaTime
            _yaw += Input.GetAxisRaw("Mouse X") * mouseSensitivity;
            _pitch -= Input.GetAxisRaw("Mouse Y") * mouseSensitivity;
            _pitch = Mathf.Clamp(_pitch, minPitch, maxPitch);
        }

        // ── 移动：相对相机方向 ─────────────────────────────────────────
        float h = Input.GetAxisRaw("Horizontal");
        float v = Input.GetAxisRaw("Vertical");

        // 相机朝向的水平投影就是"前方"
        Quaternion camYaw = Quaternion.Euler(0f, _yaw, 0f);
        Vector3 forward = camYaw * Vector3.forward;
        Vector3 right = camYaw * Vector3.right;

        Vector3 dir = forward * v + right * h;
        if (dir.sqrMagnitude > 1f) dir.Normalize();

        if (autoWalk && dir.sqrMagnitude < 1e-4f)
            dir = forward;

        bool hasInput = dir.sqrMagnitude > 1e-4f;
        if (hasInput)
        {
            _moveDir = dir;

            // 转身：只有移动时才转，站着不动保持当前朝向
            Quaternion target = Quaternion.LookRotation(dir, Vector3.up);
            transform.rotation = Quaternion.RotateTowards(transform.rotation, target,
                                                          turnSpeed * Time.deltaTime);
        }

        // 起步加速 / 松手减速：避免瞬间到速和瞬间停住，动画混合也会更顺
        float targetSpeed = hasInput
            ? moveSpeed * (Input.GetKey(KeyCode.LeftShift) ? sprintMultiplier : 1f)
            : 0f;
        float rate = targetSpeed > _currentSpeed ? acceleration : deceleration;
        _currentSpeed = Mathf.MoveTowards(_currentSpeed, targetSpeed, rate * Time.deltaTime);

        if (_currentSpeed > 1e-3f && _moveDir.sqrMagnitude > 1e-6f)
            _cc.Move(_moveDir * (_currentSpeed * Time.deltaTime));

        // 重力
        _verticalVelocity += gravity * Time.deltaTime;
        if (_cc.isGrounded && _verticalVelocity < 0f) _verticalVelocity = -2f;
        _cc.Move(Vector3.up * (_verticalVelocity * Time.deltaTime));

        // ── 动画：走路动作的播放速度跟着实际移动速度走 ─────────────────
        // 注意不能用 _cc.velocity：它反映的是「最后一次 Move()」，
        // 而最后调用的是竖直重力，水平分量永远是 0。
        // 这里用两帧之间的实际位移来测速度。
        Vector3 delta = transform.position - _lastPos;
        _lastPos = transform.position;
        delta.y = 0f;
        if (Time.deltaTime > 1e-5f) _planarSpeed = delta.magnitude / Time.deltaTime;

        if (animator != null)
        {
            float t = Mathf.Clamp(_planarSpeed / Mathf.Max(walkRefSpeed, 0.01f), 0f, 3f);
            if (_hasSpeedParam) animator.SetFloat(speedParameterName, Mathf.Clamp01(t));
            else animator.speed = t;
        }
    }

    void LateUpdate()
    {
        if (_cam == null) return;

        // 相机绕着"角色身上某个点"转，而不是绕角色原点
        Vector3 pivot = transform.position + Vector3.up * cameraTargetHeight;
        Quaternion rot = Quaternion.Euler(_pitch, _yaw, 0f);
        Vector3 back = rot * Vector3.back;                    // 从 pivot 指向相机的方向
        Vector3 desired = pivot + back * cameraDistance;

        // 遮挡检测：如果相机和角色之间挡了东西，把相机拉近
        if (cameraCollision)
        {
            Vector3 toCam = desired - pivot;
            float dist = toCam.magnitude;
            if (dist > 0.01f &&
                Physics.SphereCast(pivot, 0.25f, toCam.normalized, out RaycastHit hit,
                                   dist, ~0, QueryTriggerInteraction.Ignore))
            {
                desired = pivot + toCam.normalized * Mathf.Max(hit.distance - 0.1f, 0.6f);
            }
        }

        float k = 1f - Mathf.Exp(-cameraSmooth * Time.deltaTime);
        _cam.position = Vector3.Lerp(_cam.position, desired, k);
        _cam.rotation = Quaternion.Slerp(_cam.rotation, rot, k);
    }
}
