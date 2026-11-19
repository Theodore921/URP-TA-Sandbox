using UnityEngine;

[AddComponentMenu("草地/Timeline Locomotion Driver")]
public class TimelineLocomotionDriver : MonoBehaviour
{
    [Header("Timeline 移动根节点")]
    [Tooltip("由 Timeline 动画轨道移动的父物体。")]
    public Transform movementRoot;

    [Header("角色动画")]
    [Tooltip("使用 Locomotion 状态机的角色 Animator。")]
    public Animator animator;
    [Tooltip("Blend Tree 中控制 Idle/Walk 的浮点参数。")]
    public string speedParameter = "Speed";
    [Tooltip("Speed 参数达到 1 时对应的移动速度（米/秒）。")]
    public float walkReferenceSpeed = 2.7f;
    [Tooltip("Speed 参数平滑过渡时间。")]
    public float dampTime = 0.1f;
    [Tooltip("低于此速度时视为静止（米/秒）。")]
    public float movementThreshold = 0.05f;

    [Header("朝向")]
    [Tooltip("角色是否转向 Timeline 父物体的实际移动方向。")]
    public bool faceMovementDirection = true;
    [Tooltip("角色转向速度（度/秒）。")]
    public float turnSpeed = 720f;

    int _speedParameterHash;
    Vector3 _lastRootPosition;
    bool _isReady;

    void OnEnable()
    {
        _isReady = false;
        if (movementRoot == null || animator == null)
        {
            Debug.LogError(
                "[Timeline Locomotion] 请指定 Timeline 移动根节点和角色 Animator。",
                this);
            return;
        }

        if (string.IsNullOrEmpty(speedParameter))
        {
            Debug.LogError("[Timeline Locomotion] Speed 参数名不能为空。", this);
            return;
        }

        bool hasFloatParameter = false;
        foreach (var parameter in animator.parameters)
        {
            if (parameter.name == speedParameter &&
                parameter.type == AnimatorControllerParameterType.Float)
            {
                hasFloatParameter = true;
                break;
            }
        }

        if (!hasFloatParameter)
        {
            Debug.LogError(
                $"[Timeline Locomotion] Animator 中没有名为 '{speedParameter}' 的 Float 参数。",
                animator);
            return;
        }

        _speedParameterHash = Animator.StringToHash(speedParameter);
        _lastRootPosition = movementRoot.position;
        _isReady = true;
    }

    void LateUpdate()
    {
        if (!_isReady || movementRoot == null || animator == null)
            return;

        Vector3 rootPosition = movementRoot.position;
        Vector3 displacement = rootPosition - _lastRootPosition;
        _lastRootPosition = rootPosition;
        displacement.y = 0f;

        float deltaTime = Time.deltaTime;
        float speed = deltaTime > 1e-5f ? displacement.magnitude / deltaTime : 0f;
        if (speed < movementThreshold)
            speed = 0f;

        float normalizedSpeed = Mathf.Clamp01(speed / Mathf.Max(walkReferenceSpeed, 0.01f));
        animator.SetFloat(_speedParameterHash, normalizedSpeed, dampTime, deltaTime);

        if (faceMovementDirection && speed > 0f)
        {
            Quaternion targetRotation = Quaternion.LookRotation(displacement.normalized, Vector3.up);
            transform.rotation = Quaternion.RotateTowards(
                transform.rotation,
                targetRotation,
                turnSpeed * deltaTime);
        }
    }

    void OnDisable()
    {
        if (_isReady && animator != null)
            animator.SetFloat(_speedParameterHash, 0f);
    }
}
