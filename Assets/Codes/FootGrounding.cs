using UnityEngine;

/// <summary>
/// 运行时脚部贴地修正。
/// 在 Animator 求值之后（LateUpdate）对双腿做解析式两骨 IK，
/// 把陷进地面的脚拉回地面，不修改任何动画资源。
/// </summary>
[RequireComponent(typeof(Animator))]
public class FootGrounding : MonoBehaviour
{
    [Header("Ground")]
    [Tooltip("地面层，默认全部")]
    public LayerMask groundMask = ~0;
    public float maxRayDistance = 3f;
    [Tooltip("射线没打到东西时的兜底地面高度")]
    public float groundYFallback = 0f;

    [Header("Foot")]
    [Tooltip("踝关节到鞋底的高度。<=0 时按初始姿势自动计算")]
    public float ankleHeight = -1f;
    [Tooltip("额外留出的离地间隙")]
    public float extraClearance = 0.004f;

    [Header("Solve")]
    [Tooltip("勾选后只处理“脚陷进地面”，不把悬空的脚往下拽，避免破坏步态")]
    public bool onlyFixPenetration = true;
    [Tooltip("单脚单帧最大修正距离，防止异常帧把腿拉爆")]
    public float maxCorrection = 0.12f;
    [Tooltip("打开后记录最后一次求解过程，便于排查")]
    public bool debugLog = false;
    [HideInInspector] public string lastDebug = "";

    Animator anim;
    Transform lUpper, lLower, lFoot;
    Transform rUpper, rLower, rFoot;

    void Awake()
    {
        anim = GetComponent<Animator>();
        CacheBones();
    }

    void CacheBones()
    {
        if (anim == null) anim = GetComponent<Animator>();
        if (anim == null || !anim.isHuman) return;

        lUpper = anim.GetBoneTransform(HumanBodyBones.LeftUpperLeg);
        lLower = anim.GetBoneTransform(HumanBodyBones.LeftLowerLeg);
        lFoot = anim.GetBoneTransform(HumanBodyBones.LeftFoot);
        rUpper = anim.GetBoneTransform(HumanBodyBones.RightUpperLeg);
        rLower = anim.GetBoneTransform(HumanBodyBones.RightLowerLeg);
        rFoot = anim.GetBoneTransform(HumanBodyBones.RightFoot);

        if (ankleHeight <= 0f && lFoot != null)
        {
            var smr = GetComponentInChildren<SkinnedMeshRenderer>();
            if (smr != null) ankleHeight = Mathf.Max(0.02f, lFoot.position.y - smr.bounds.min.y);
            else ankleHeight = 0.1f;
        }
    }

    void LateUpdate()
    {
        SolveOnce();
    }

    /// <summary>手动执行一次修正，方便在编辑器里验证。</summary>
    public void SolveOnce()
    {
        if (lFoot == null) CacheBones();
        if (lFoot == null || lUpper == null) return;

        SolveLeg(lUpper, lLower, lFoot);
        SolveLeg(rUpper, rLower, rFoot);
    }

    float SampleGroundY(Vector3 near)
    {
        Vector3 origin = new Vector3(near.x, near.y + maxRayDistance * 0.5f, near.z);
        var hits = Physics.RaycastAll(origin, Vector3.down, maxRayDistance, groundMask);
        float best = float.NegativeInfinity;
        for (int i = 0; i < hits.Length; i++)
        {
            var col = hits[i].collider;
            if (col == null) continue;
            if (col.transform.root == transform.root) continue; // 忽略自己身上的碰撞体
            if (hits[i].point.y > best) best = hits[i].point.y;
        }
        return best > float.NegativeInfinity ? best : groundYFallback;
    }

    void SolveLeg(Transform upper, Transform lower, Transform foot)
    {
        if (upper == null || lower == null || foot == null) return;

        float groundY = SampleGroundY(foot.position);
        float desiredY = groundY + ankleHeight + extraClearance;

        Vector3 ankle = foot.position;
        if (onlyFixPenetration && ankle.y >= desiredY)
        {
            if (debugLog) lastDebug = "skip: ankle.y=" + ankle.y.ToString("F4") + " >= desired " + desiredY.ToString("F4");
            return;
        }
        if (debugLog) lastDebug = "run: ankle.y=" + ankle.y.ToString("F4") + " desired=" + desiredY.ToString("F4") + " ground=" + groundY.ToString("F3");

        if (ankle.y < desiredY - maxCorrection) desiredY = ankle.y + maxCorrection;

        Vector3 hip = upper.position;
        Vector3 knee = lower.position;
        Vector3 target = new Vector3(ankle.x, desiredY, ankle.z);

        float L1 = (knee - hip).magnitude;
        float L2 = (ankle - knee).magnitude;
        if (L1 < 1e-4f || L2 < 1e-4f) return;

        Vector3 toTarget = target - hip;
        float rawDist = toTarget.magnitude;
        if (rawDist < 1e-4f) return;
        float d = Mathf.Clamp(rawDist, Mathf.Abs(L1 - L2) + 1e-3f, L1 + L2 - 1e-3f);
        Vector3 dir = toTarget / rawDist;

        // 保持原来的弯曲平面，避免膝盖左右乱扭
        Vector3 pole = knee - hip;
        pole -= dir * Vector3.Dot(pole, dir);
        if (pole.sqrMagnitude < 1e-6f) pole = upper.forward - dir * Vector3.Dot(upper.forward, dir);
        if (pole.sqrMagnitude < 1e-6f) pole = Vector3.forward;
        pole.Normalize();
        Vector3 axis = Vector3.Cross(dir, pole).normalized;

        float cosA = Mathf.Clamp((L1 * L1 + d * d - L2 * L2) / (2f * L1 * d), -1f, 1f);
        float aDeg = Mathf.Acos(cosA) * Mathf.Rad2Deg;

        Vector3 thighA = Quaternion.AngleAxis(aDeg, axis) * dir;
        Vector3 thighB = Quaternion.AngleAxis(-aDeg, axis) * dir;
        Vector3 kneeA = hip + thighA * L1;
        Vector3 kneeB = hip + thighB * L1;
        Vector3 thighDir = (kneeA - knee).sqrMagnitude <= (kneeB - knee).sqrMagnitude ? thighA : thighB;

        Quaternion footWorldRot = foot.rotation; // 保留脚掌朝向

        upper.rotation = Quaternion.FromToRotation((knee - hip).normalized, thighDir) * upper.rotation;

        Vector3 kneeNew = lower.position;
        Vector3 ankleNew = foot.position;
        Vector3 shinNow = ankleNew - kneeNew;
        if (shinNow.sqrMagnitude < 1e-8f) return;
        Vector3 shinWant = target - kneeNew;
        if (shinWant.sqrMagnitude < 1e-8f) return;

        lower.rotation = Quaternion.FromToRotation(shinNow.normalized, shinWant.normalized) * lower.rotation;

        foot.rotation = footWorldRot;
    }
}
